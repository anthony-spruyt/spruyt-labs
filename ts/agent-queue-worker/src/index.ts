import { createServer, type Server } from "node:http";
import { Worker, Queue, QueueEvents } from "bullmq";
import { Redis } from "ioredis";
import { loadConfig } from "./config.js";
import { Processor } from "./processor.js";
import { Router } from "./routes.js";
import { logger } from "./logger.js";
import * as metrics from "./metrics.js";
import { extractRole } from "./types.js";
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
const processor = new Processor(redis, config);

const worker = new Worker("agent", async (job) => processor.process(job), {
  ...queueOpts,
  concurrency: 1,
  stalledInterval: 60_000,
  lockDuration: 120_000,
  maxStalledCount: 1,
});

const queueEvents = new QueueEvents("agent", queueOpts);

queueEvents.on("deduplicated", ({ deduplicatedJobId }) => {
  metrics.dedupCounter.inc({
    queue: "agent",
    role: extractRole(deduplicatedJobId),
  });
});

worker.on("completed", async (job) => {
  if (job) await redis.set(`agent:completed:${job.id}`, "1", "EX", 3600);
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

const router = new Router(queue, redis, processor, config, isReady);

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
  await new Promise<void>((resolve) => server.close(() => resolve()));

  await worker.close();
  await queueEvents.close();
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
