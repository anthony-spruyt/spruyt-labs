import type { Server } from "node:http";
import type { Queue, Worker } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "../config.js";
import { fetchReposWithRevertLabels } from "../github.js";
import { logger } from "../logger.js";
import * as metrics from "../metrics.js";
import type { Processor } from "../processor.js";
import type { RoleRegistry } from "../roles/registry.js";
import { sreTriagedKey } from "../roles/sre-alert-role.js";
import type { CircuitBreaker } from "./guard.js";
import { DEFAULT_JOB_OPTIONS } from "./options.js";

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

  worker.on("error", (err) => {
    logger.error("BullMQ worker error", { error: String(err) });
  });

  worker.on("completed", async (job) => {
    if (!job) return;

    let roleDef: ReturnType<typeof registry.get>;
    try {
      roleDef = registry.get(job.data.role);
    } catch (err) {
      logger.error("Unknown role in completed job", {
        jobId: job.id,
        role: job.data.role,
        error: String(err),
      });
      return;
    }
    if (!roleDef.bufferKey || !roleDef.drainBuffer) return;

    const suppressedFingerprints = new Set<string>();

    if (job.data.role === "sre-alert") {
      const suppressTtl = Number(
        job.data.data?.triage_suppress_s ?? config.SRE_TRIAGE_SUPPRESS_S
      );

      if (job.data.data?.fingerprint) {
        suppressedFingerprints.add(String(job.data.data.fingerprint));
      }
      const processedAlerts = job.data.data?.alerts as
        | Array<Record<string, unknown>>
        | undefined;
      if (processedAlerts) {
        for (const a of processedAlerts) {
          if (a.fingerprint) suppressedFingerprints.add(String(a.fingerprint));
        }
      }

      if (suppressedFingerprints.size > 0 && suppressTtl > 0) {
        try {
          const pipeline = redis.pipeline();
          for (const fp of suppressedFingerprints) {
            pipeline.set(
              sreTriagedKey(job.data.repo, fp),
              "1",
              "EX",
              suppressTtl
            );
          }
          await pipeline.exec();
          logger.debug("Wrote triaged markers", {
            jobId: job.id,
            count: suppressedFingerprints.size,
            ttlSeconds: suppressTtl,
          });
        } catch (err) {
          logger.warn("Failed to write triaged markers", {
            jobId: job.id,
            error: String(err),
          });
        }
      }
    }

    try {
      const drainedData = await roleDef.drainBuffer(job.id!, job.data, redis);
      let alerts = drainedData.data?.alerts as
        | Array<Record<string, unknown>>
        | undefined;
      if (!alerts || alerts.length === 0) return;

      if (suppressedFingerprints.size > 0) {
        alerts = alerts.filter(
          (a) =>
            !a.fingerprint || !suppressedFingerprints.has(String(a.fingerprint))
        );
        if (alerts.length === 0) {
          try {
            await job.remove();
          } catch {
            // Already cleaned up by removeOnComplete
          }
          logger.debug("All buffered alerts already suppressed", {
            jobId: job.id,
          });
          return;
        }
        drainedData.data = { ...drainedData.data, alerts };
      }

      try {
        await job.remove();
      } catch {
        // Already cleaned up by removeOnComplete
      }

      const { dispatch_state: _, dispatched_at: __, ...baseData } = drainedData;
      const cooldown = roleDef.cooldownMs ?? 0;
      try {
        await queue.add(job.data.role, baseData, {
          ...DEFAULT_JOB_OPTIONS,
          ...roleDef.jobOptions,
          jobId: job.id!,
          priority: job.data.priority,
          ...(cooldown > 0 && { delay: cooldown }),
        });
        logger.info("Auto-queued SRE job from buffer drain", {
          jobId: job.id,
          alertCount: alerts.length,
          delayMs: cooldown,
        });
      } catch {
        const bufKey = roleDef.bufferKey!(job.id!);
        await redis.rpush(bufKey, ...alerts.map((a) => JSON.stringify(a)));
        await redis.ltrim(bufKey, -config.SRE_BATCH_MAX_SIZE, -1);
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
      metrics.jobExhausted.inc({
        queue: "agent-jobs",
        role,
        repo: job.data.repo,
      });
      logger.error("Job exhausted all attempts", {
        jobId: job.id,
        role,
        repo: job.data.repo,
        error: err.message,
      });
    } else {
      metrics.jobFailures.inc({
        queue: "agent-jobs",
        role,
        reason: "job_failed",
      });
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
      metrics.queueDepth.set({ queue: "agent-jobs" }, waiting + prioritized);
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

  process.on("uncaughtException", (err) => {
    logger.error("Uncaught exception", {
      error: String(err),
      stack: err.stack,
    });
    metrics.workerShutdowns.inc();
    process.exit(1);
  });

  process.on("unhandledRejection", (reason) => {
    logger.error("Unhandled rejection", { error: String(reason) });
  });

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
