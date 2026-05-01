import { createServer, type Server } from "node:http";
import { Worker, Queue } from "bullmq";
import { Redis } from "ioredis";
import { loadConfig } from "./config.js";
import { Processor } from "./processor.js";
import { Router } from "./routes.js";
import { logger } from "./logger.js";
import * as metrics from "./metrics.js";
import { createDefaultRegistry } from "./roles/registry.js";
import { fetchReposWithRevertLabels } from "./github.js";

const config = loadConfig();

const redis = new Redis({
  host: config.VALKEY_HOST,
  port: config.VALKEY_PORT,
  password: config.VALKEY_PASSWORD,
  maxRetriesPerRequest: null,
  retryStrategy: (times: number) => Math.min(times * 500, 5000),
});

const connection = {
  host: config.VALKEY_HOST,
  port: config.VALKEY_PORT,
  password: config.VALKEY_PASSWORD,
};

const queueOpts = { connection, prefix: "agent:queue" };

const queue = new Queue("agent", queueOpts);
const registry = createDefaultRegistry();
const processor = new Processor(redis, config, registry);

const worker = new Worker("agent", async (job) => processor.process(job), {
  ...queueOpts,
  concurrency: 1,
  stalledInterval: 120_000,
  lockDuration: 120_000,
  maxStalledCount: 2,
});

worker.on("completed", async (job) => {
  if (!job) return;
  await redis.set(`agent:completed:${job.id}`, "1", "EX", 3600);

  const roleDef = registry.get(job.data.role);
  if (!roleDef.bufferKey || !roleDef.drainBuffer) return;

  try {
    const drainedData = await roleDef.drainBuffer(job.id!, job.data, redis);
    const alerts = drainedData.payload?.buffered_alerts as
      | unknown[]
      | undefined;
    if (!alerts || alerts.length === 0) return;

    await redis.del(`agent:completed:${job.id}`);
    try {
      await job.remove();
    } catch {
      // Already cleaned up by removeOnComplete
    }

    const { dispatch_state: _, dispatched_at: __, ...baseData } = drainedData;
    try {
      await queue.add(job.data.role, baseData, {
        jobId: job.id!,
        attempts: 2,
        backoff: { type: "exponential", delay: 30_000 },
        removeOnComplete: { age: 3600 },
        removeOnFail: { age: 604_800, count: 500 },
        priority: job.data.priority,
      });
      logger.info("Auto-queued SRE job from buffer drain", {
        jobId: job.id,
        alertCount: alerts.length,
      });
    } catch {
      // Re-push drained alerts so next drainBuffer picks them up
      const bufKey = roleDef.bufferKey!(job.id!);
      for (const alert of alerts) {
        await redis.rpush(bufKey, JSON.stringify(alert));
      }
      await redis.ltrim(bufKey, -50, -1);
      await redis.expire(bufKey, 3600);
      logger.warn("Re-pushed alerts after failed auto-queue", {
        jobId: job.id,
        alertCount: alerts.length,
      });
    }
  } catch (err) {
    logger.warn("SRE buffer drain failed", {
      jobId: job.id,
      error: String(err),
    });
  }
});

worker.on("failed", async (job, err) => {
  if (!job) return;
  const role = job.data.role ?? "unknown";

  await redis.zadd(
    `agent:circuit:${job.data.repo}`,
    Date.now(),
    `${job.id}:${job.attemptsMade}`
  );
  await redis.expire(`agent:circuit:${job.data.repo}`, 3600);

  if (job.attemptsMade >= (job.opts.attempts ?? 1)) {
    metrics.jobExhausted.inc({ queue: "agent", role, repo: job.data.repo });
    logger.error("Job exhausted all attempts", {
      jobId: job.id,
      role,
      repo: job.data.repo,
      error: err.message,
    });
  } else {
    metrics.jobFailures.inc({ queue: "agent", role, reason: "job_failed" });
    logger.warn("Job failed, will retry", {
      jobId: job.id,
      role,
      repo: job.data.repo,
      attempt: job.attemptsMade,
      error: err.message,
    });
  }
});

const isReady = () => redis.status === "ready" && !worker.closing;

const router = new Router(queue, redis, processor, config, isReady, registry);

const server: Server = createServer(async (req, res) => {
  try {
    await router.handle(req, res);
  } catch (err) {
    logger.error("Unhandled route error", { error: String(err) });
    if (!res.headersSent) {
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Internal server error" }));
    }
  }
});

async function updateQueueDepth(): Promise<void> {
  try {
    const waiting = await queue.getWaitingCount();
    const prioritized = await queue.getJobCountByTypes("prioritized");
    metrics.queueDepth.set({ queue: "agent" }, waiting + prioritized);
  } catch {
    // Valkey blip — skip this tick
  }
}

const depthInterval = setInterval(updateQueueDepth, 15_000);

async function startupReconciliation(): Promise<void> {
  try {
    logger.info("Running startup reconciliation");
    const depths = await fetchReposWithRevertLabels(
      config.GITHUB_OWNER,
      config.GITHUB_TOKEN
    );
    for (const [repo, count] of depths) {
      await redis.set(`agent:revert-depth:${repo}`, String(count), "EX", 3600);
    }
    logger.info("Startup reconciliation complete", {
      reposWithReverts: depths.size,
    });
  } catch (err) {
    logger.warn("Startup reconciliation failed — proceeding without", {
      error: String(err),
    });
  }
}

async function shutdown(): Promise<void> {
  logger.info("Shutting down");
  metrics.workerShutdowns.inc();

  clearInterval(depthInterval);
  processor.cancelAll();
  await new Promise<void>((resolve) => server.close(() => resolve()));

  await worker.close();
  await queue.close();
  await redis.quit();

  logger.info("Shutdown complete");
  process.exit(0);
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

server.listen(config.PORT, async () => {
  logger.info("Worker started", { port: config.PORT });
  await startupReconciliation();
});
