import { randomUUID } from "node:crypto";
import type { Job, Worker } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "./config.js";
import { checkDependencies } from "./health.js";
import type { AgentJob, JobResult } from "./job/schema.js";
import { logger } from "./logger.js";
import * as metrics from "./metrics.js";
import type { RoleRegistry } from "./roles/registry.js";

// Lua script for atomic session token validation (check -> delete -> accept).
// Eliminates TOCTOU gap. Token consumed on first valid use — replay-proof.
// Uses Redis EVAL command (server-side Lua execution), not JavaScript eval().
const VALIDATE_SESSION_LUA = `
local stored = redis.call('GET', KEYS[1])
if stored == false then
  return 'expired_or_missing'
elseif stored ~= ARGV[1] then
  return 'mismatch'
else
  redis.call('DEL', KEYS[1])
  return 'valid'
end
`;

type CallbackResolver = (result: JobResult) => void;

export class Processor {
  private callbacks = new Map<string, CallbackResolver>();
  private redis: Redis;
  private config: Config;
  private registry: RoleRegistry;
  private worker!: Worker;

  constructor(redis: Redis, config: Config, registry: RoleRegistry) {
    this.redis = redis;
    this.config = config;
    this.registry = registry;
  }

  setWorker(worker: Worker): void {
    this.worker = worker;
  }

  async process(job: Job<AgentJob>): Promise<JobResult> {
    const { role, repo } = job.data;
    const roleDef = this.registry.get(role);
    const timeout = roleDef.timeoutMs;
    const timeoutSec = Math.ceil(timeout / 1000);
    const fields = { jobId: job.id!, role, repo };

    const locked = await this.redis.set(
      `agent:active:${job.id}`,
      "1",
      "EX",
      timeoutSec,
      "NX"
    );
    if (!locked) {
      logger.warn("Duplicate processing detected", fields);
      return { status: "duplicate" };
    }

    try {
      const cached = await this.redis.get(
        `agent:result:${job.id}:${job.attemptsMade}`
      );
      if (cached) {
        logger.info("Returning cached result", fields);
        await this.redis.del(`agent:result:${job.id}:${job.attemptsMade}`);
        return JSON.parse(cached) as JobResult;
      }

      if (roleDef.checkStaleness) {
        const staleness = await roleDef.checkStaleness(job.data, this.config);
        if (staleness.stale) {
          logger.info("Job stale", { ...fields, reason: staleness.reason });
          metrics.staleDiscards.inc({ queue: "agent-jobs", role });
          return { status: "stale" };
        }
      }

      const dispatchState = job.data.dispatch_state ?? "pending";
      let needsDispatch = dispatchState !== "dispatched";

      if (!needsDispatch) {
        const sessionAlive = await this.redis.exists(`agent:session:${job.id}`);
        if (!sessionAlive) {
          logger.info("Session expired, re-dispatching", fields);
          needsDispatch = true;
        }
      }

      if (needsDispatch) {
        await checkDependencies(this.config, this.worker, job);
      }

      logger.info("Processing job", {
        ...fields,
        dispatchState,
        needsDispatch,
        attempt: job.attemptsMade,
      });

      const timer = metrics.jobDuration.startTimer({
        queue: "agent-jobs",
        role,
      });
      const deadline = this.rejectAfter(
        timeout,
        `Job ${job.id} timed out after ${timeout}ms`
      );
      // Extend BullMQ lock every 30s to prevent stalled-job false positives
      // during long async callback waits (lockDuration=120s, jobs run up to 60min)
      const lockExtender = setInterval(async () => {
        try {
          if (!job.token) {
            logger.warn("Job token missing, skipping lock extension", {
              jobId: job.id,
            });
            return;
          }
          await job.extendLock(job.token, 120_000);
        } catch (err) {
          logger.warn("Failed to extend job lock", {
            jobId: job.id,
            error: String(err),
          });
        }
      }, 30_000);

      try {
        const result = await Promise.race([
          needsDispatch
            ? this.dispatchAndAwaitCallback(job.id!, job.data, job)
            : this.awaitCallbackWithCachePoll(job.id!, job.attemptsMade),
          deadline.promise,
        ]);

        if (result.status === "cancelled")
          throw new Error("Job cancelled during shutdown");

        logger.info("Job completed", { ...fields, status: result.status });
        return result;
      } catch (err) {
        const reason =
          err instanceof Error && err.message.includes("timed out")
            ? "timeout"
            : "error";
        if (reason === "timeout") {
          metrics.jobTimeouts.inc({ queue: "agent-jobs", role });
        } else {
          metrics.jobFailures.inc({
            queue: "agent-jobs",
            role,
            reason: "processor_error",
          });
        }
        logger.error("Job failed", { ...fields, error: String(err) });
        throw err;
      } finally {
        clearInterval(lockExtender);
        deadline.clear();
        timer();
        const resolver = this.callbacks.get(job.id!);
        if (resolver) resolver({ status: "cancelled" });
        this.callbacks.delete(job.id!);
      }
    } finally {
      await this.redis.del(`agent:active:${job.id}`, `agent:session:${job.id}`);
    }
  }

  cancelAll(): void {
    for (const [jobId, resolver] of this.callbacks) {
      resolver({ status: "cancelled" });
      this.callbacks.delete(jobId);
    }
  }

  async resolveCallback(jobId: string, result: JobResult): Promise<boolean> {
    const resolver = this.callbacks.get(jobId);
    if (resolver) {
      resolver(result);
      this.callbacks.delete(jobId);
      return true;
    }
    return false;
  }

  async cacheResult(
    jobId: string,
    attempt: number,
    result: JobResult
  ): Promise<void> {
    await this.redis.set(
      `agent:result:${jobId}:${attempt}`,
      JSON.stringify(result),
      "EX",
      3600
    );
  }

  async validateSession(jobId: string, token: string): Promise<string> {
    const key = `agent:session:${jobId}`;
    // Redis EVAL runs Lua server-side for atomic check-delete-accept
    return (await this.redis.eval(
      VALIDATE_SESSION_LUA,
      1,
      key,
      token
    )) as string;
  }

  private async dispatchAndAwaitCallback(
    jobId: string,
    data: AgentJob,
    job: Job<AgentJob>
  ): Promise<JobResult> {
    const dispatched_at = new Date().toISOString();
    const session_token = randomUUID();
    const roleDef = this.registry.get(data.role);
    const timeoutSec = Math.ceil(roleDef.timeoutMs / 1000);

    let dispatchData = data;
    if (roleDef.drainBuffer) {
      dispatchData = await roleDef.drainBuffer(jobId, data, this.redis);
      if (dispatchData !== data) {
        await job.updateData(dispatchData);
      }
    }

    await this.redis.set(
      `agent:session:${jobId}`,
      session_token,
      "EX",
      timeoutSec
    );

    const resp = await fetch(this.config.N8N_DISPATCH_WEBHOOK, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.config.WORKER_TO_N8N_SECRET}`,
        "Idempotency-Key": `${jobId}:${job.attemptsMade}`,
      },
      body: JSON.stringify({
        ...dispatchData,
        job_id: jobId,
        session_token,
        attempt: job.attemptsMade,
        dispatched_at,
        timeout_seconds: timeoutSec,
      }),
    });

    if (!resp.ok) {
      await job.updateData({
        ...dispatchData,
        dispatch_state: "failed",
        dispatched_at,
      });
      throw new Error(`Dispatch failed: ${resp.status} ${resp.statusText}`);
    }

    await job.updateData({
      ...dispatchData,
      dispatch_state: "dispatched",
      dispatched_at,
    });
    logger.info("Dispatched to n8n", {
      jobId,
      role: dispatchData.role,
      repo: dispatchData.repo,
    });

    return this.awaitCallback(jobId);
  }

  private awaitCallback(jobId: string): Promise<JobResult> {
    return new Promise((resolve) => {
      this.callbacks.set(jobId, resolve);
    });
  }

  private awaitCallbackWithCachePoll(
    jobId: string,
    attemptsMade: number
  ): Promise<JobResult> {
    return new Promise((resolve) => {
      let resolved = false;
      let poll: NodeJS.Timeout | undefined;

      const settle = (result: JobResult) => {
        if (resolved) return;
        resolved = true;
        if (poll) clearInterval(poll);
        this.callbacks.delete(jobId);
        resolve(result);
      };

      this.callbacks.set(jobId, settle);

      poll = setInterval(async () => {
        try {
          const cached = await this.redis.get(
            `agent:result:${jobId}:${attemptsMade}`
          );
          if (cached) settle(JSON.parse(cached) as JobResult);
        } catch {
          // Valkey blip during poll — retry on next interval
        }
      }, 15_000);
    });
  }

  private rejectAfter(
    ms: number,
    message: string
  ): { promise: Promise<never>; clear: () => void } {
    let timer: NodeJS.Timeout;
    const promise = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error(message)), ms);
    });
    return { promise, clear: () => clearTimeout(timer!) };
  }
}
