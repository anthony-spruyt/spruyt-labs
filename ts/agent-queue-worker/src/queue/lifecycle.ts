import type { Server } from "node:http";
import type { Worker, Queue } from "bullmq";
import type { Redis } from "ioredis";
import type { Processor } from "../processor.js";
import type { RoleRegistry } from "../roles/registry.js";
import type { CircuitBreaker } from "./guard.js";
import type { Config } from "../config.js";
import { fetchReposWithRevertLabels } from "../github.js";
import { DEFAULT_JOB_OPTIONS } from "./options.js";
import { logger } from "../logger.js";
import * as metrics from "../metrics.js";

export interface LifecycleDeps {
  worker: Worker;
  queue: Queue;
  redis: Redis;
  processor: Processor;
  registry: RoleRegistry;
  circuitBreaker: CircuitBreaker;
  server: Server;
  config: Config;
}

export function setupLifecycle(deps: LifecycleDeps): void {
  const {
    worker,
    queue,
    redis,
    processor,
    registry,
    circuitBreaker,
    server,
    config,
  } = deps;

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
          ...DEFAULT_JOB_OPTIONS,
          jobId: job.id!,
          priority: job.data.priority,
        });
        logger.info("Auto-queued SRE job from buffer drain", {
          jobId: job.id,
          alertCount: alerts.length,
        });
      } catch {
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

    await circuitBreaker.trip(job.data.repo, job.id!, job.attemptsMade);

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

  const depthInterval = setInterval(async () => {
    try {
      const waiting = await queue.getWaitingCount();
      const prioritized = await queue.getJobCountByTypes("prioritized");
      metrics.queueDepth.set({ queue: "agent" }, waiting + prioritized);
    } catch {
      // Valkey blip — skip this tick
    }
  }, 15_000);

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
    await startupReconciliation(config, redis);
  });
}

async function startupReconciliation(
  config: Config,
  redis: Redis
): Promise<void> {
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
