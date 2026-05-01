import { type IncomingMessage, type ServerResponse } from "node:http";
import { Queue } from "bullmq";
import type { Redis } from "ioredis";
import {
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
} from "./job/schema.js";
import type { AgentJob } from "./job/schema.js";
import { buildJobIdentity } from "./job/identity.js";
import type { RoleRegistry } from "./roles/registry.js";
import type { JobState } from "./roles/types.js";
import type { Processor } from "./processor.js";
import { logger } from "./logger.js";
import * as metrics from "./metrics.js";
import type { Config } from "./config.js";

// Atomic state-checked update: only HSET if job is still in wait/prioritized/paused.
// The non-atomic getJob+getState before this call is acceptable because this Lua
// re-validates state atomically — the outer check is an optimization to avoid
// unnecessary EVAL calls, not a correctness dependency.
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

export class Router {
  private queue: Queue;
  private redis: Redis;
  private processor: Processor;
  private config: Config;
  private isReady: () => boolean;
  private registry: RoleRegistry;

  constructor(
    queue: Queue,
    redis: Redis,
    processor: Processor,
    config: Config,
    isReady: () => boolean,
    registry: RoleRegistry
  ) {
    this.queue = queue;
    this.redis = redis;
    this.processor = processor;
    this.config = config;
    this.isReady = isReady;
    this.registry = registry;
  }

  async handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
    const path = url.pathname;
    const method = req.method ?? "GET";

    if (method === "GET" && path === "/livez")
      return this.json(res, 200, { status: "ok" });
    if (method === "GET" && path === "/readyz") {
      return this.json(res, this.isReady() ? 200 : 503, {
        ready: this.isReady(),
      });
    }
    if (method === "GET" && path === "/metrics") {
      res.writeHead(200, { "Content-Type": metrics.registry.contentType });
      res.end(await metrics.registry.metrics());
      return;
    }

    if (!this.authenticate(req))
      return this.json(res, 401, { error: "Unauthorized" });

    if (method === "POST" && path === "/jobs") return this.addJob(req, res);

    const jobMatch = path.match(/^\/jobs\/([^/]+)\/(done|fail|retry)$/);
    if (method === "POST" && jobMatch) {
      const [, jobId, action] = jobMatch;
      if (action === "done")
        return this.completeJob(req, res, decodeURIComponent(jobId!));
      if (action === "fail")
        return this.failJob(req, res, decodeURIComponent(jobId!));
      if (action === "retry")
        return this.retryJob(res, decodeURIComponent(jobId!));
    }

    const circuitMatch = path.match(/^\/circuit\/([^/]+)\/reset$/);
    if (method === "POST" && circuitMatch) {
      return this.resetCircuit(res, decodeURIComponent(circuitMatch[1]!));
    }

    this.json(res, 404, { error: "Not found" });
  }

  private async addJob(
    req: IncomingMessage,
    res: ServerResponse
  ): Promise<void> {
    let body: unknown;
    try {
      body = await this.readBody(req);
    } catch (err) {
      if (err instanceof SyntaxError)
        return this.json(res, 400, { added: false, reason: "malformed_json" });
      throw err;
    }
    const parsed = AgentJobSchema.safeParse(body);
    if (!parsed.success) {
      return this.json(res, 400, {
        added: false,
        reason: "invalid_request",
        errors: parsed.error.issues,
      });
    }

    const data = parsed.data;

    const circuitKey = `agent:circuit:${data.repo}`;
    await this.redis.zremrangebyscore(
      circuitKey,
      "-inf",
      Date.now() - 3_600_000
    );
    const recentFailures = await this.redis.zcount(
      circuitKey,
      Date.now() - 3_600_000,
      "+inf"
    );
    if (recentFailures >= 5) {
      logger.warn("Circuit open", {
        repo: data.repo,
        failures: recentFailures,
      });
      return this.json(res, 429, { added: false, reason: "circuit_open" });
    }

    const rateKey = `agent:rate:${data.repo}`;
    await this.redis.zremrangebyscore(rateKey, "-inf", Date.now() - 3_600_000);
    const rateCount = await this.redis.zcard(rateKey);
    if (rateCount >= 10) {
      logger.warn("Rate limited", { repo: data.repo, count: rateCount });
      return this.json(res, 429, { added: false, reason: "rate_limited" });
    }

    const identity = buildJobIdentity(data, this.registry);
    const jobId = identity.jobId;
    const roleDef = this.registry.get(data.role);

    const completed = await this.redis.exists(`agent:completed:${jobId}`);
    if (completed) {
      return this.json(res, 409, {
        added: false,
        reason: "recently_completed",
      });
    }

    const existingJob = await this.queue.getJob(jobId);
    if (existingJob) {
      const state = (await existingJob.getState()) as JobState;
      const defaultAction =
        state === "waiting" || state === "prioritized"
          ? ({ action: "replace" } as const)
          : ({ action: "discard" } as const);
      const decision =
        roleDef.onDuplicate?.(existingJob.data, data, state) ?? defaultAction;

      if (decision.action === "discard") {
        metrics.dedupActionCounter.inc({
          queue: "agent",
          role: data.role,
          action: "discard",
        });
        return this.json(res, 409, {
          added: false,
          reason: state === "active" ? "active" : "deduplicated",
        });
      }

      if (decision.action === "buffer") {
        const bufKey = roleDef.bufferKey!(jobId);
        await this.redis.rpush(bufKey, JSON.stringify(data.payload));
        await this.redis.ltrim(bufKey, -50, -1);
        await this.redis.expire(bufKey, 3600);
        metrics.dedupActionCounter.inc({
          queue: "agent",
          role: data.role,
          action: "buffer",
        });
        return this.json(res, 202, {
          added: false,
          buffered: true,
          jobId,
        });
      }

      // "replace" — shallow merge, atomic Lua validates state before HSET
      const merged = JSON.stringify({ ...existingJob.data, ...data });
      const updated = await this.atomicUpdateIfWaiting(jobId, merged);
      if (updated) {
        metrics.dedupActionCounter.inc({
          queue: "agent",
          role: data.role,
          action: "replace",
        });
        return this.json(res, 200, {
          added: false,
          replaced: true,
          jobId,
        });
      }
      // Job transitioned to active between getState and Lua — fall through to create new
    }

    try {
      await this.queue.add(data.role, data, {
        jobId,
        attempts: 2,
        backoff: { type: "exponential", delay: 30_000 },
        removeOnComplete: { age: 3600 },
        removeOnFail: { age: 604_800, count: 500 },
        priority: data.priority,
      });

      await this.redis.zadd(rateKey, Date.now(), jobId);
      await this.redis.expire(rateKey, 3600);

      logger.info("Job added", { jobId, role: data.role, repo: data.repo });
      this.json(res, 201, { added: true, jobId });
    } catch (err) {
      if (isDuplicateJobError(err)) {
        metrics.dedupActionCounter.inc({
          queue: "agent",
          role: data.role,
          action: "discard",
        });
        return this.json(res, 409, {
          added: false,
          reason: "deduplicated",
        });
      }
      logger.error("Failed to add job", { jobId, error: String(err) });
      this.json(res, 503, {
        added: false,
        reason: "internal_error",
      });
    }
  }

  private async atomicUpdateIfWaiting(
    jobId: string,
    mergedData: string
  ): Promise<boolean> {
    const prefix = (this.queue.opts.prefix ?? "bull") as string;
    const name = this.queue.name;
    // Redis EVAL runs Lua server-side for atomic state check + update
    const result = await this.redis.eval(
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

  private async completeJob(
    req: IncomingMessage,
    res: ServerResponse,
    jobId: string
  ): Promise<void> {
    let body: unknown;
    try {
      body = await this.readBody(req);
    } catch (err) {
      if (err instanceof SyntaxError)
        return this.json(res, 400, {
          accepted: false,
          reason: "malformed_json",
        });
      throw err;
    }
    const parsed = DoneRequestSchema.safeParse(body);
    if (!parsed.success) {
      return this.json(res, 400, {
        accepted: false,
        reason: "invalid_request",
      });
    }

    const { result, session_token, attempt } = parsed.data;

    const validation = await this.processor.validateSession(
      jobId,
      attempt,
      session_token
    );
    if (validation === "expired_or_missing") {
      const job = await this.queue.getJob(jobId);
      if (job && (await job.isCompleted())) {
        return this.json(res, 200, { accepted: true, already_completed: true });
      }
      return this.json(res, 403, {
        accepted: false,
        reason: "invalid_session",
      });
    }
    if (validation === "mismatch") {
      return this.json(res, 403, {
        accepted: false,
        reason: "invalid_session",
      });
    }

    const job = await this.queue.getJob(jobId);
    if (
      job &&
      job.data.dispatched_at &&
      job.data.dispatched_at !== parsed.data.dispatched_at
    ) {
      await this.processor.cacheResult(jobId, attempt, {
        status: "completed",
        ...result,
      });
      logger.info("Cached stale dispatch result", { jobId, attempt });
      return this.json(res, 200, { accepted: true, stale_dispatch: true });
    }

    const resolved = await this.processor.resolveCallback(jobId, {
      status: "completed",
      ...result,
    });
    if (!resolved) {
      await this.processor.cacheResult(jobId, attempt, {
        status: "completed",
        ...result,
      });
      logger.info("Cached result for re-processing", { jobId, attempt });
    }

    logger.info("Job done callback received", { jobId });
    this.json(res, 200, { accepted: true });
  }

  private async failJob(
    req: IncomingMessage,
    res: ServerResponse,
    jobId: string
  ): Promise<void> {
    let body: unknown;
    try {
      body = await this.readBody(req);
    } catch (err) {
      if (err instanceof SyntaxError)
        return this.json(res, 400, {
          accepted: false,
          reason: "malformed_json",
        });
      throw err;
    }
    const parsed = FailRequestSchema.safeParse(body);
    if (!parsed.success) {
      return this.json(res, 400, {
        accepted: false,
        reason: "invalid_request",
      });
    }

    const resolved = await this.processor.resolveCallback(jobId, {
      status: "failed",
      reason: parsed.data.reason,
    });
    if (!resolved) {
      logger.warn("No active callback for fail", { jobId });
    }

    logger.info("Job fail callback received", {
      jobId,
      reason: parsed.data.reason,
    });
    this.json(res, 200, { accepted: true });
  }

  private async retryJob(res: ServerResponse, jobId: string): Promise<void> {
    const job = await this.queue.getJob(jobId);
    if (!job)
      return this.json(res, 404, { retried: false, reason: "not_found" });
    if (!(await job.isFailed()))
      return this.json(res, 200, { retried: false, reason: "not_failed" });

    await job.retry();
    logger.info("Job retried manually", { jobId });
    this.json(res, 200, { retried: true });
  }

  private async resetCircuit(res: ServerResponse, repo: string): Promise<void> {
    const deleted = await this.redis.del(`agent:circuit:${repo}`);
    logger.info("Circuit reset", { repo, wasOpen: deleted > 0 });
    this.json(res, 200, { reset: deleted > 0 });
  }

  private authenticate(req: IncomingMessage): boolean {
    const auth = req.headers.authorization;
    return auth === `Bearer ${this.config.N8N_TO_WORKER_SECRET}`;
  }

  private json(res: ServerResponse, status: number, data: unknown): void {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(data));
  }

  private readBody(req: IncomingMessage): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const chunks: Buffer[] = [];
      let size = 0;
      req.on("data", (chunk: Buffer) => {
        size += chunk.length;
        if (size > 1_048_576) {
          req.destroy(new Error("Body too large"));
          return;
        }
        chunks.push(chunk);
      });
      req.on("end", () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString()));
        } catch {
          reject(new SyntaxError("Malformed JSON body"));
        }
      });
      req.on("error", reject);
    });
  }
}

function isDuplicateJobError(err: unknown): boolean {
  if (err instanceof Error) {
    return err.message.includes("Duplicate") || err.message.includes("exists");
  }
  return false;
}
