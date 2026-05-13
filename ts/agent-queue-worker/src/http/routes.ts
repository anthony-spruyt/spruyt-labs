import type { IncomingMessage, ServerResponse } from "node:http";
import type { Queue } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "../config.js";
import { buildJobIdentity } from "../job/identity.js";
import {
  AgentJobInputSchema,
  DoneRequestSchema,
  FailRequestSchema,
  toAgentJob,
} from "../job/schema.js";
import { logger } from "../logger.js";
import * as metrics from "../metrics.js";
import type { Processor } from "../processor.js";
import type { CircuitBreaker, RateLimiter } from "../queue/guard.js";
import { DEFAULT_JOB_OPTIONS } from "../queue/options.js";
import type { RoleRegistry } from "../roles/registry.js";
import { sreTriagedKey } from "../roles/sre-alert-role.js";
import type { JobState } from "../roles/types.js";
import { resolveDuplicateAction } from "../roles/types.js";
import { json, parseAndValidate } from "./middleware.js";

// Atomic state-checked update: only HSET if job is still in wait/prioritized/paused.
// The non-atomic getJob+getState before this call is acceptable because this Lua
// re-validates state atomically -- the outer check is an optimization to avoid
// unnecessary EVAL calls, not a correctness dependency.
// NOTE: Does not check the BullMQ delayed sorted set. This is safe because no
// onDuplicate implementation returns "replace" for delayed jobs (SRE alerts always
// return "buffer"; all other roles discard non-waiting/prioritized states). If a
// future role needs to replace delayed jobs, extend this script to check the delayed set.
// Uses Redis EVAL command (server-side Lua execution), not JavaScript eval().
const ATOMIC_UPDATE_IF_WAITING_LUA = `
local inWait   = redis.call('LPOS', KEYS[1], ARGV[2])
local inPrio   = redis.call('ZSCORE', KEYS[2], ARGV[2])
local inPaused = redis.call('LPOS', KEYS[3], ARGV[2])
if inWait ~= false or inPrio ~= false or inPaused ~= false then
  redis.call('HSET', KEYS[4], 'data', ARGV[1])
  return 1
end
return 0
`;

export interface RouteDeps {
  queue: Queue;
  redis: Redis;
  processor: Processor;
  registry: RoleRegistry;
  circuitBreaker: CircuitBreaker;
  rateLimiter: RateLimiter;
  config: Config;
}

export async function handleAddJob(
  req: IncomingMessage,
  res: ServerResponse,
  deps: RouteDeps
): Promise<void> {
  const result = await parseAndValidate(req, res, AgentJobInputSchema, {
    added: false,
  });
  if (!result.ok) return;
  const data = toAgentJob(result.data);

  const circuit = await deps.circuitBreaker.check(data.repo);
  if (circuit.open) {
    return json(res, 429, { added: false, reason: "circuit_open" });
  }

  if (data.role === "sre-alert" && data.data?.fingerprint) {
    const fpKey = sreTriagedKey(data.repo, String(data.data.fingerprint));
    const triaged = await deps.redis.exists(fpKey);
    if (triaged) {
      metrics.sreSuppressed.inc({ role: data.role });
      return json(res, 200, { added: false, reason: "already_triaged" });
    }
  }

  const identity = buildJobIdentity(data, deps.registry);
  const roleDef = deps.registry.get(data.role);
  const jobId = identity.jobId;

  const existingJob = await deps.queue.getJob(jobId);
  if (existingJob) {
    const state = await existingJob.getState();

    if (state === "completed") {
      const shouldBuffer = !!roleDef.bufferKey;
      if (shouldBuffer) {
        const bufKey = roleDef.bufferKey!(jobId);
        await deps.redis.rpush(bufKey, JSON.stringify(data.data));
        await deps.redis.ltrim(bufKey, -deps.config.SRE_BATCH_MAX_SIZE, -1);
        await deps.redis.expire(bufKey, 3600);

        try {
          await existingJob.remove();
        } catch {
          // Already cleaned up by removeOnComplete
        }
        const { dispatch_state: _, dispatched_at: __, ...baseData } = data;
        try {
          await deps.queue.add(data.role, baseData, {
            ...DEFAULT_JOB_OPTIONS,
            ...roleDef.jobOptions,
            jobId,
            priority: data.priority,
            delay: roleDef.cooldownMs ?? 300_000,
          });
        } catch (err) {
          if (!isDuplicateJobError(err)) throw err;
        }

        metrics.dedupActionCounter.inc({
          queue: "agent-jobs",
          role: data.role,
          action: "buffer",
        });
        return json(res, 202, { added: false, buffered: true, job_id: jobId });
      }
      try {
        await existingJob.remove();
      } catch {
        // Already cleaned up by removeOnComplete
      }
    } else {
      const decision = resolveDuplicateAction(
        roleDef,
        existingJob.data,
        data,
        state as JobState
      );

      if (decision.action === "discard") {
        metrics.dedupActionCounter.inc({
          queue: "agent-jobs",
          role: data.role,
          action: "discard",
        });
        return json(res, 200, {
          added: false,
          reason: state === "active" ? "active" : "deduplicated",
        });
      }

      if (decision.action === "buffer") {
        const bufKey = roleDef.bufferKey!(jobId);
        await deps.redis.rpush(bufKey, JSON.stringify(data.data));
        await deps.redis.ltrim(bufKey, -deps.config.SRE_BATCH_MAX_SIZE, -1);
        await deps.redis.expire(bufKey, 3600);
        metrics.dedupActionCounter.inc({
          queue: "agent-jobs",
          role: data.role,
          action: "buffer",
        });
        return json(res, 202, { added: false, buffered: true, job_id: jobId });
      }

      // "replace" — shallow merge replaces top-level keys (including `data`)
      // entirely with incoming values; nested objects are NOT deep-merged.
      const merged = JSON.stringify({ ...existingJob.data, ...data });
      const updated = await atomicUpdateIfWaiting(
        deps.queue,
        deps.redis,
        jobId,
        merged
      );
      if (updated) {
        metrics.dedupActionCounter.inc({
          queue: "agent-jobs",
          role: data.role,
          action: "replace",
        });
        return json(res, 200, { added: false, replaced: true, job_id: jobId });
      }
    }
  }

  const rate = await deps.rateLimiter.check(data.repo);
  if (rate.limited) {
    return json(res, 429, { added: false, reason: "rate_limited" });
  }

  try {
    const delay = roleDef.getJobDelay?.(data) ?? 0;
    await deps.queue.add(data.role, data, {
      ...DEFAULT_JOB_OPTIONS,
      ...roleDef.jobOptions,
      jobId,
      priority: data.priority,
      ...(delay > 0 && { delay }),
    });

    await deps.rateLimiter.record(data.repo, jobId);

    logger.info("Job added", { jobId, role: data.role, repo: data.repo });
    json(res, 201, { added: true, job_id: jobId });
  } catch (err) {
    if (isDuplicateJobError(err)) {
      metrics.dedupActionCounter.inc({
        queue: "agent-jobs",
        role: data.role,
        action: "discard",
      });
      return json(res, 200, { added: false, reason: "deduplicated" });
    }
    logger.error("Failed to add job", { jobId, error: String(err) });
    json(res, 503, { added: false, reason: "internal_error" });
  }
}

export async function handleCompleteJob(
  req: IncomingMessage,
  res: ServerResponse,
  jobId: string,
  deps: RouteDeps
): Promise<void> {
  const result = await parseAndValidate(req, res, DoneRequestSchema, {
    accepted: false,
  });
  if (!result.ok) return;

  const { result: jobResult, session_token } = result.data;

  const validation = await deps.processor.validateSession(jobId, session_token);
  if (validation === "expired_or_missing") {
    const job = await deps.queue.getJob(jobId);
    if (job && (await job.isCompleted())) {
      return json(res, 200, { accepted: true, already_completed: true });
    }
    return json(res, 403, { accepted: false, reason: "invalid_session" });
  }
  if (validation === "mismatch") {
    return json(res, 403, { accepted: false, reason: "invalid_session" });
  }

  const job = await deps.queue.getJob(jobId);
  const attempt = job?.attemptsMade ?? 0;

  const resolved = await deps.processor.resolveCallback(jobId, {
    status: "completed",
    ...jobResult,
  });
  if (!resolved) {
    await deps.processor.cacheResult(jobId, attempt, {
      status: "completed",
      ...jobResult,
    });
    logger.info("Cached result for re-processing", { jobId, attempt });
  }

  logger.info("Job done callback received", { jobId });
  json(res, 200, { accepted: true });
}

export async function handleFailJob(
  req: IncomingMessage,
  res: ServerResponse,
  jobId: string,
  deps: RouteDeps
): Promise<void> {
  const result = await parseAndValidate(req, res, FailRequestSchema, {
    accepted: false,
  });
  if (!result.ok) return;

  const resolved = await deps.processor.resolveCallback(jobId, {
    status: "failed",
    reason: result.data.reason,
  });
  if (!resolved) {
    logger.warn("No active callback for fail", { jobId });
  }

  logger.info("Job fail callback received", {
    jobId,
    reason: result.data.reason,
  });
  json(res, 200, { accepted: true });
}

export async function handleRetryJob(
  res: ServerResponse,
  jobId: string,
  deps: RouteDeps
): Promise<void> {
  const job = await deps.queue.getJob(jobId);
  if (!job) return json(res, 404, { retried: false, reason: "not_found" });
  if (!(await job.isFailed()))
    return json(res, 200, { retried: false, reason: "not_failed" });

  await job.retry();
  logger.info("Job retried manually", { jobId });
  json(res, 200, { retried: true });
}

export async function handleGetJob(
  res: ServerResponse,
  jobId: string,
  deps: RouteDeps
): Promise<void> {
  const job = await deps.queue.getJob(jobId);
  if (!job) return json(res, 404, { error: "not_found" });

  const [state, sessionToken] = await Promise.all([
    job.getState(),
    deps.redis.get(`agent:session:${jobId}`),
  ]);

  json(res, 200, {
    ...job.data,
    job_id: job.id,
    state,
    session_token: sessionToken,
    attempt: job.attemptsMade,
    timestamp: job.timestamp,
    processedOn: job.processedOn,
    finishedOn: job.finishedOn,
  });
}

export async function handleResetCircuit(
  res: ServerResponse,
  repo: string,
  deps: RouteDeps
): Promise<void> {
  const wasOpen = await deps.circuitBreaker.reset(repo);
  json(res, 200, { reset: wasOpen });
}

async function atomicUpdateIfWaiting(
  queue: Queue,
  redis: Redis,
  jobId: string,
  mergedData: string
): Promise<boolean> {
  const prefix = (queue.opts.prefix ?? "bull") as string;
  const name = queue.name;
  // Redis EVAL runs Lua server-side for atomic state check + update
  const result = await redis.eval(
    ATOMIC_UPDATE_IF_WAITING_LUA,
    4,
    `${prefix}:${name}:wait`,
    `${prefix}:${name}:prioritized`,
    `${prefix}:${name}:paused`,
    `${prefix}:${name}:${jobId}`,
    mergedData,
    jobId
  );
  return result === 1;
}

function isDuplicateJobError(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const msg = err.message;
  return (
    msg.includes("Job already exists with id") || msg.includes("Duplicate")
  );
}
