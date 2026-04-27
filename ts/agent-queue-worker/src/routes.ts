import { type IncomingMessage, type ServerResponse } from "node:http";
import { Queue } from "bullmq";
import type { Redis } from "ioredis";
import {
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
  buildJobId,
} from "./types.js";
import type { Processor } from "./processor.js";
import { logger } from "./logger.js";
import * as metrics from "./metrics.js";
import type { Config } from "./config.js";

export class Router {
  private queue: Queue;
  private redis: Redis;
  private processor: Processor;
  private config: Config;
  private isReady: () => boolean;

  constructor(
    queue: Queue,
    redis: Redis,
    processor: Processor,
    config: Config,
    isReady: () => boolean
  ) {
    this.queue = queue;
    this.redis = redis;
    this.processor = processor;
    this.config = config;
    this.isReady = isReady;
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

    const jobId = buildJobId(data);

    const completed = await this.redis.exists(`agent:completed:${jobId}`);
    if (completed) {
      return this.json(res, 409, {
        added: false,
        reason: "recently_completed",
      });
    }

    const active = await this.redis.exists(`agent:active:${jobId}`);
    if (active) {
      return this.json(res, 409, { added: false, reason: "active" });
    }

    const entity = String(data.pr_number ?? data.issue_number ?? "");
    if (entity && data.role !== "execute")
      await this.supersedeOlderJobs(
        data.repo,
        entity,
        data.head_sha,
        data.role
      );

    try {
      await this.queue.add(data.role, data, {
        jobId,
        deduplication: { id: jobId },
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
      logger.error("Failed to add job", { jobId, error: String(err) });
      this.json(res, 503, {
        added: false,
        reason: "internal_error",
      });
    }
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

  private async supersedeOlderJobs(
    repo: string,
    entity: string,
    currentSha: string,
    role: string
  ): Promise<void> {
    const candidates = [
      ...(await this.queue.getJobs(["prioritized"])),
      ...(await this.queue.getJobs(["waiting"])),
    ];
    for (const job of candidates) {
      if (
        job.data.repo === repo &&
        String(job.data.pr_number ?? job.data.issue_number) === entity &&
        job.data.role === role &&
        job.data.head_sha !== currentSha
      ) {
        try {
          await job.remove();
          logger.info("Superseded older job", {
            oldJobId: job.id,
            newSha: currentSha,
          });
        } catch {
          // Job may have transitioned to active between scan and remove
        }
      }
    }
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
