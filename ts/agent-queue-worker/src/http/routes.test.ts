import { EventEmitter } from "node:events";
import type { IncomingMessage, ServerResponse } from "node:http";
import { describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import {
  handleAddJob,
  handleCompleteJob,
  handleFailJob,
  handleGetJob,
  handleResetCircuit,
  handleRetryJob,
  type RouteDeps,
} from "./routes.js";

function mockRes(): ServerResponse & { _status: number; _body: unknown } {
  const res = {
    _status: 0,
    _body: null as unknown,
    writeHead(status: number) {
      res._status = status;
      return res;
    },
    end(data: string) {
      res._body = JSON.parse(data);
    },
  } as unknown as ServerResponse & { _status: number; _body: unknown };
  return res;
}

function mockReq(body: unknown): IncomingMessage {
  const emitter = new EventEmitter();
  process.nextTick(() => {
    emitter.emit("data", Buffer.from(JSON.stringify(body)));
    emitter.emit("end");
  });
  return emitter as unknown as IncomingMessage;
}

const jobData = {
  role: "renovate-triage" as const,
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  data: { pr_number: 42, head_sha: "abc", action: "opened" },
  dispatch_state: "dispatched" as const,
  dispatched_at: "2026-01-01T00:00:00Z",
};

describe("handleGetJob", () => {
  it("returns job data with session token", async () => {
    const res = mockRes();
    const getJob = vi.fn().mockResolvedValue({
      id: "org/repo--triage-42",
      data: jobData,
      attemptsMade: 1,
      timestamp: 1700000000000,
      processedOn: 1700000001000,
      finishedOn: undefined,
      getState: vi.fn().mockResolvedValue("active"),
    });
    const redisGet = vi
      .fn()
      .mockResolvedValue("00000000-0000-0000-0000-000000000001");
    const deps = {
      queue: { getJob },
      redis: { get: redisGet },
    } as unknown as RouteDeps;

    await handleGetJob(res, "org/repo--triage-42", deps);

    expect(getJob).toHaveBeenCalledWith("org/repo--triage-42");
    expect(redisGet).toHaveBeenCalledWith("agent:session:org/repo--triage-42");
    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.job_id).toBe("org/repo--triage-42");
    expect(body.state).toBe("active");
    expect(body.repo).toBe("org/repo");
    expect(body.role).toBe("renovate-triage");
    expect(body.data).toEqual({
      pr_number: 42,
      head_sha: "abc",
      action: "opened",
    });
    expect(body.session_token).toBe("00000000-0000-0000-0000-000000000001");
    expect(body.attempt).toBe(1);
  });

  it("returns null session_token when expired", async () => {
    const res = mockRes();
    const redisGet = vi.fn().mockResolvedValue(null);
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          id: "org/repo--triage-42",
          data: jobData,
          attemptsMade: 0,
          timestamp: 1700000000000,
          processedOn: undefined,
          finishedOn: undefined,
          getState: vi.fn().mockResolvedValue("waiting"),
        }),
      },
      redis: { get: redisGet },
    } as unknown as RouteDeps;

    await handleGetJob(res, "org/repo--triage-42", deps);

    expect(redisGet).toHaveBeenCalledWith("agent:session:org/repo--triage-42");
    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).session_token).toBeNull();
  });

  it("returns 404 for unknown job", async () => {
    const res = mockRes();
    const getJob = vi.fn().mockResolvedValue(null);
    const deps = { queue: { getJob } } as unknown as RouteDeps;

    await handleGetJob(res, "nonexistent", deps);

    expect(getJob).toHaveBeenCalledWith("nonexistent");
    expect(res._status).toBe(404);
    expect((res._body as Record<string, unknown>).error).toBe("not_found");
  });
});

describe("handleAddJob suppression", () => {
  const sreAlert = {
    role: "sre-alert" as const,
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    data: { fingerprint: "fp-abc123" },
  };

  function makeDeps(overrides: Record<string, unknown> = {}): RouteDeps {
    return {
      queue: { getJob: vi.fn().mockResolvedValue(null), add: vi.fn() },
      redis: { exists: vi.fn().mockResolvedValue(0) },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          cooldownMs: 300_000,
          jobOptions: { attempts: 1 },
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          getJobDelay: () => 0,
        }),
      },
      config: {
        SRE_BATCH_MAX_SIZE: 50,
        SRE_BATCH_WINDOW_MS: 60_000,
        SRE_COOLDOWN_MS: 300_000,
        SRE_TRIAGE_SUPPRESS_S: 3600,
      } as Config,
      processor: {},
      ...overrides,
    } as unknown as RouteDeps;
  }

  it("suppresses triaged SRE alert with 200", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const deps = makeDeps({
      redis: { exists: vi.fn().mockResolvedValue(1) },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).reason).toBe(
      "already_triaged"
    );
  });

  it("does not suppress non-triaged SRE alert", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const deps = makeDeps();

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(201);
    expect((res._body as Record<string, unknown>).added).toBe(true);
  });

  it("returns 200 when duplicate job is active (discard)", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const deps = makeDeps({
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: sreAlert,
          getState: vi.fn().mockResolvedValue("active"),
        }),
        add: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          onDuplicate: () => ({ action: "discard" }),
        }),
      },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("active");
  });

  it("returns 200 when duplicate job is delayed (discard)", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const deps = makeDeps({
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: sreAlert,
          getState: vi.fn().mockResolvedValue("delayed"),
        }),
        add: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          onDuplicate: () => ({ action: "discard" }),
        }),
      },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("deduplicated");
  });

  it("returns 200 when BullMQ throws duplicate job error", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const deps = makeDeps({
      queue: {
        getJob: vi.fn().mockResolvedValue(null),
        add: vi
          .fn()
          .mockRejectedValue(
            new Error("Job already exists with id org/repo--sre-alert")
          ),
      },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("deduplicated");
  });

  it("does not suppress non-SRE role with fingerprint", async () => {
    const res = mockRes();
    const req = mockReq({
      role: "renovate-triage",
      repo: "org/repo",
      event_type: "pull_request",
      priority: 5,
      data: { pr_number: 1, head_sha: "abc" },
    });
    const deps = makeDeps({
      redis: { exists: vi.fn().mockResolvedValue(1) },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 120_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--renovate-triage--1`,
          getJobDelay: () => 0,
        }),
      },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(201);
    expect((res._body as Record<string, unknown>).added).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// handleAddJob — circuit breaker & rate limiter
// ---------------------------------------------------------------------------

describe("handleAddJob circuit breaker and rate limiter", () => {
  const renovateJob = {
    role: "renovate-triage" as const,
    repo: "org/repo",
    event_type: "pull_request",
    priority: 5,
    data: { pr_number: 1, head_sha: "abc123" },
  };

  function makeDeps(overrides: Record<string, unknown> = {}): RouteDeps {
    return {
      queue: { getJob: vi.fn().mockResolvedValue(null), add: vi.fn() },
      redis: { exists: vi.fn().mockResolvedValue(0) },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 120_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--renovate-triage--1`,
          getJobDelay: () => 0,
        }),
      },
      config: { SRE_BATCH_MAX_SIZE: 50 } as Config,
      processor: {},
      ...overrides,
    } as unknown as RouteDeps;
  }

  it("returns 429 with circuit_open when circuit breaker is open", async () => {
    const res = mockRes();
    const req = mockReq(renovateJob);
    const deps = makeDeps({
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: true }) },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(429);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("circuit_open");
  });

  it("returns 429 with rate_limited when rate limiter fires", async () => {
    const res = mockRes();
    const req = mockReq(renovateJob);
    const deps = makeDeps({
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: true }),
        record: vi.fn(),
      },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(429);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("rate_limited");
  });

  it("returns 400 when request body fails schema validation", async () => {
    const res = mockRes();
    // Missing required data fields
    const req = mockReq({
      role: "renovate-triage",
      repo: "org/repo",
      event_type: "pr",
      priority: 5,
      data: {},
    });
    const deps = makeDeps();

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(400);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("invalid_request");
  });

  it("returns 400 for malformed JSON body", async () => {
    const res = mockRes();
    const emitter = new EventEmitter();
    process.nextTick(() => {
      emitter.emit("data", Buffer.from("not valid json {{{"));
      emitter.emit("end");
    });
    const req = emitter as unknown as IncomingMessage;
    const deps = makeDeps();

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(400);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.reason).toBe("malformed_json");
  });
});

// ---------------------------------------------------------------------------
// handleAddJob — completed job with bufferKey (buffer-on-complete path)
// ---------------------------------------------------------------------------

describe("handleAddJob buffer-on-complete path", () => {
  const sreAlert = {
    role: "sre-alert" as const,
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    data: { fingerprint: "fp-xyz" },
  };

  it("buffers data and re-queues job when completed job has bufferKey", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const remove = vi.fn().mockResolvedValue(undefined);
    const add = vi.fn().mockResolvedValue(undefined);
    const rpush = vi.fn().mockResolvedValue(1);
    const ltrim = vi.fn().mockResolvedValue("OK");
    const expire = vi.fn().mockResolvedValue(1);

    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: sreAlert,
          getState: vi.fn().mockResolvedValue("completed"),
          remove,
        }),
        add,
        opts: { prefix: "bull" },
        name: "agent-jobs",
      },
      redis: {
        exists: vi.fn().mockResolvedValue(0),
        rpush,
        ltrim,
        expire,
      },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          cooldownMs: 300_000,
          jobOptions: { attempts: 1 },
          bufferKey: (id: string) => `sre:buffer:${id}`,
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          getJobDelay: () => 0,
        }),
      },
      config: { SRE_BATCH_MAX_SIZE: 50 } as Config,
      processor: {},
    } as unknown as RouteDeps;

    await handleAddJob(req, res, deps);

    expect(rpush).toHaveBeenCalled();
    expect(ltrim).toHaveBeenCalled();
    expect(expire).toHaveBeenCalled();
    expect(res._status).toBe(202);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.buffered).toBe(true);
    expect(typeof body.job_id).toBe("string");
  });

  it("removes completed job and falls through to add when no bufferKey", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const remove = vi.fn().mockResolvedValue(undefined);
    const add = vi.fn().mockResolvedValue(undefined);

    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: sreAlert,
          getState: vi.fn().mockResolvedValue("completed"),
          remove,
        }),
        add,
        opts: { prefix: "bull" },
        name: "agent-jobs",
      },
      redis: { exists: vi.fn().mockResolvedValue(0) },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          getJobDelay: () => 0,
          // No bufferKey
        }),
      },
      config: { SRE_BATCH_MAX_SIZE: 50 } as Config,
      processor: {},
    } as unknown as RouteDeps;

    await handleAddJob(req, res, deps);

    expect(remove).toHaveBeenCalled();
    expect(add).toHaveBeenCalled();
    expect(res._status).toBe(201);
    expect((res._body as Record<string, unknown>).added).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// handleAddJob — buffer action for non-completed existing job
// ---------------------------------------------------------------------------

describe("handleAddJob buffer action (waiting job)", () => {
  const sreAlert = {
    role: "sre-alert" as const,
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    data: { fingerprint: "fp-buffer" },
  };

  it("buffers alert data and returns 202 when buffer action returned for waiting job", async () => {
    const res = mockRes();
    const req = mockReq(sreAlert);
    const rpush = vi.fn().mockResolvedValue(1);
    const ltrim = vi.fn().mockResolvedValue("OK");
    const expire = vi.fn().mockResolvedValue(1);

    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: sreAlert,
          getState: vi.fn().mockResolvedValue("waiting"),
        }),
        add: vi.fn(),
        opts: { prefix: "bull" },
        name: "agent-jobs",
      },
      redis: {
        exists: vi.fn().mockResolvedValue(0),
        rpush,
        ltrim,
        expire,
      },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          jobOptions: {},
          bufferKey: (id: string) => `sre:buffer:${id}`,
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          onDuplicate: () => ({ action: "buffer" }),
        }),
      },
      config: { SRE_BATCH_MAX_SIZE: 50 } as Config,
      processor: {},
    } as unknown as RouteDeps;

    await handleAddJob(req, res, deps);

    expect(rpush).toHaveBeenCalled();
    expect(ltrim).toHaveBeenCalled();
    expect(expire).toHaveBeenCalled();
    expect(res._status).toBe(202);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.buffered).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// handleAddJob — replace action with atomicUpdateIfWaiting
// ---------------------------------------------------------------------------

describe("handleAddJob replace action", () => {
  const renovateJob = {
    role: "renovate-triage" as const,
    repo: "org/repo",
    event_type: "pull_request",
    priority: 5,
    data: { pr_number: 1, head_sha: "newsha" },
  };

  it("returns 200 with replaced:true when atomic update succeeds", async () => {
    const res = mockRes();
    const req = mockReq(renovateJob);

    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: { ...renovateJob, data: { pr_number: 1, head_sha: "oldsha" } },
          getState: vi.fn().mockResolvedValue("waiting"),
        }),
        add: vi.fn(),
        opts: { prefix: "bull" },
        name: "agent-jobs",
      },
      redis: {
        exists: vi.fn().mockResolvedValue(0),
        // eval returns 1 = updated successfully
        eval: vi.fn().mockResolvedValue(1),
      },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 120_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--renovate-triage--1`,
          onDuplicate: () => ({ action: "replace" }),
        }),
      },
      config: { SRE_BATCH_MAX_SIZE: 50 } as Config,
      processor: {},
    } as unknown as RouteDeps;

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.added).toBe(false);
    expect(body.replaced).toBe(true);
    expect(typeof body.job_id).toBe("string");
  });

  it("falls through to add when atomic update returns 0 (job left waiting state)", async () => {
    const res = mockRes();
    const req = mockReq(renovateJob);
    const add = vi.fn().mockResolvedValue(undefined);

    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          data: { ...renovateJob, data: { pr_number: 1, head_sha: "oldsha" } },
          getState: vi.fn().mockResolvedValue("waiting"),
        }),
        add,
        opts: { prefix: "bull" },
        name: "agent-jobs",
      },
      redis: {
        exists: vi.fn().mockResolvedValue(0),
        // eval returns 0 = not updated (job moved out of waiting before Lua ran)
        eval: vi.fn().mockResolvedValue(0),
      },
      circuitBreaker: { check: vi.fn().mockResolvedValue({ open: false }) },
      rateLimiter: {
        check: vi.fn().mockResolvedValue({ limited: false }),
        record: vi.fn(),
      },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 120_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--renovate-triage--1`,
          onDuplicate: () => ({ action: "replace" }),
          getJobDelay: () => 0,
        }),
      },
      config: { SRE_BATCH_MAX_SIZE: 50 } as Config,
      processor: {},
    } as unknown as RouteDeps;

    await handleAddJob(req, res, deps);

    expect(add).toHaveBeenCalled();
    expect(res._status).toBe(201);
    expect((res._body as Record<string, unknown>).added).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// handleCompleteJob
// ---------------------------------------------------------------------------

// Zod v4 enforces strict UUID format: version 1-8 in segment 3, variant 8/9/a/b in segment 4.
const VALID_UUID = "39ce4e3d-a79c-48eb-ac53-5914334cbdef";

describe("handleCompleteJob", () => {
  const validBody = {
    result: { summary: "done" },
    session_token: VALID_UUID,
  };

  function makeProcessor(validateResult: string, resolveResult = true) {
    return {
      validateSession: vi.fn().mockResolvedValue(validateResult),
      resolveCallback: vi.fn().mockResolvedValue(resolveResult),
      cacheResult: vi.fn().mockResolvedValue(undefined),
    };
  }

  it("returns 200 accepted:true when session is valid and callback resolves", async () => {
    const res = mockRes();
    const req = mockReq(validBody);
    const processor = makeProcessor("valid", true);
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({ attemptsMade: 1 }),
      },
      processor,
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-123", deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.accepted).toBe(true);
    expect(processor.resolveCallback).toHaveBeenCalledWith(
      "job-123",
      expect.objectContaining({ status: "completed", summary: "done" })
    );
  });

  it("caches result when no active callback (resolve returns false)", async () => {
    const res = mockRes();
    const req = mockReq(validBody);
    const processor = makeProcessor("valid", false);
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({ attemptsMade: 2 }),
      },
      processor,
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-456", deps);

    // resolveCallback must be called first (and return false) before cacheResult
    const resolveOrder = processor.resolveCallback.mock.invocationCallOrder[0]!;
    const cacheOrder = processor.cacheResult.mock.invocationCallOrder[0]!;
    expect(resolveOrder).toBeLessThan(cacheOrder);

    expect(processor.resolveCallback).toHaveBeenCalledWith(
      "job-456",
      expect.objectContaining({ status: "completed", summary: "done" })
    );
    expect(processor.cacheResult).toHaveBeenCalledWith(
      "job-456",
      2,
      expect.objectContaining({ status: "completed", summary: "done" })
    );
    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).accepted).toBe(true);
  });

  it("returns 200 already_completed:true when session expired but job is completed", async () => {
    const res = mockRes();
    const req = mockReq(validBody);
    const processor = makeProcessor("expired_or_missing");
    const isCompleted = vi.fn().mockResolvedValue(true);
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({ isCompleted }),
      },
      processor,
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-789", deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.accepted).toBe(true);
    expect(body.already_completed).toBe(true);
  });

  it("returns 403 invalid_session when session expired and job not completed", async () => {
    const res = mockRes();
    const req = mockReq(validBody);
    const processor = makeProcessor("expired_or_missing");
    const isCompleted = vi.fn().mockResolvedValue(false);
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({ isCompleted }),
      },
      processor,
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-expired", deps);

    expect(res._status).toBe(403);
    const body = res._body as Record<string, unknown>;
    expect(body.accepted).toBe(false);
    expect(body.reason).toBe("invalid_session");
  });

  it("returns 403 invalid_session when session expired and job not found", async () => {
    const res = mockRes();
    const req = mockReq(validBody);
    const processor = makeProcessor("expired_or_missing");
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue(null),
      },
      processor,
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-gone", deps);

    expect(res._status).toBe(403);
    const body = res._body as Record<string, unknown>;
    expect(body.reason).toBe("invalid_session");
  });

  it("returns 403 invalid_session on token mismatch", async () => {
    const res = mockRes();
    const req = mockReq(validBody);
    const processor = makeProcessor("mismatch");
    const deps = {
      queue: { getJob: vi.fn() },
      processor,
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-mismatch", deps);

    expect(res._status).toBe(403);
    expect((res._body as Record<string, unknown>).reason).toBe(
      "invalid_session"
    );
  });

  it("returns 400 when body is missing required session_token", async () => {
    const res = mockRes();
    const req = mockReq({ result: { summary: "done" } }); // no session_token
    const deps = {
      queue: { getJob: vi.fn() },
      processor: makeProcessor("valid"),
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-bad", deps);

    expect(res._status).toBe(400);
    const body = res._body as Record<string, unknown>;
    expect(body.accepted).toBe(false);
    expect(body.reason).toBe("invalid_request");
  });

  it("returns 400 when session_token is not a UUID", async () => {
    const res = mockRes();
    const req = mockReq({ result: {}, session_token: "not-a-uuid" });
    const deps = {
      queue: { getJob: vi.fn() },
      processor: makeProcessor("valid"),
    } as unknown as RouteDeps;

    await handleCompleteJob(req, res, "job-bad-token", deps);

    expect(res._status).toBe(400);
    const body2 = res._body as Record<string, unknown>;
    expect(body2.reason).toBe("invalid_request");
    expect(body2.accepted).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// handleFailJob
// ---------------------------------------------------------------------------

describe("handleFailJob", () => {
  it("returns 200 accepted:true when callback resolves", async () => {
    const res = mockRes();
    const req = mockReq({ reason: "timeout" });
    const deps = {
      processor: {
        resolveCallback: vi.fn().mockResolvedValue(true),
      },
    } as unknown as RouteDeps;

    await handleFailJob(req, res, "job-123", deps);

    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).accepted).toBe(true);
  });

  it("returns 200 accepted:true even when no active callback (resolve returns false)", async () => {
    const res = mockRes();
    const req = mockReq({ reason: "agent_crashed" });
    const deps = {
      processor: {
        resolveCallback: vi.fn().mockResolvedValue(false),
      },
    } as unknown as RouteDeps;

    await handleFailJob(req, res, "job-no-callback", deps);

    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).accepted).toBe(true);
  });

  it("returns 400 when reason is missing", async () => {
    const res = mockRes();
    const req = mockReq({});
    const deps = {
      processor: { resolveCallback: vi.fn() },
    } as unknown as RouteDeps;

    await handleFailJob(req, res, "job-bad", deps);

    expect(res._status).toBe(400);
    const body = res._body as Record<string, unknown>;
    expect(body.accepted).toBe(false);
    expect(body.reason).toBe("invalid_request");
  });

  it("returns 400 when reason is empty string", async () => {
    const res = mockRes();
    const req = mockReq({ reason: "" });
    const deps = {
      processor: { resolveCallback: vi.fn() },
    } as unknown as RouteDeps;

    await handleFailJob(req, res, "job-empty-reason", deps);

    expect(res._status).toBe(400);
    expect((res._body as Record<string, unknown>).reason).toBe(
      "invalid_request"
    );
  });

  it("passes reason from request body to resolveCallback", async () => {
    const res = mockRes();
    const req = mockReq({ reason: "n8n_dispatch_failed" });
    const resolveCallback = vi.fn().mockResolvedValue(true);
    const deps = {
      processor: { resolveCallback },
    } as unknown as RouteDeps;

    await handleFailJob(req, res, "job-abc", deps);

    expect(resolveCallback).toHaveBeenCalledWith(
      "job-abc",
      expect.objectContaining({
        status: "failed",
        reason: "n8n_dispatch_failed",
      })
    );
  });
});

// ---------------------------------------------------------------------------
// handleRetryJob
// ---------------------------------------------------------------------------

describe("handleRetryJob", () => {
  it("returns 404 when job does not exist", async () => {
    const res = mockRes();
    const deps = {
      queue: { getJob: vi.fn().mockResolvedValue(null) },
    } as unknown as RouteDeps;

    await handleRetryJob(res, "nonexistent-job", deps);

    expect(res._status).toBe(404);
    const body = res._body as Record<string, unknown>;
    expect(body.retried).toBe(false);
    expect(body.reason).toBe("not_found");
  });

  it("returns 200 retried:false when job is active", async () => {
    const res = mockRes();
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          getState: vi.fn().mockResolvedValue("active"),
        }),
      },
    } as unknown as RouteDeps;

    await handleRetryJob(res, "active-job", deps);

    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.retried).toBe(false);
    expect(body.reason).toBe("already_queued");
  });

  it("re-queues completed job", async () => {
    const res = mockRes();
    const remove = vi.fn().mockResolvedValue(undefined);
    const add = vi.fn().mockResolvedValue(undefined);
    const jobData = { role: "renovate-triage", repo: "org/repo", priority: 1 };
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          getState: vi.fn().mockResolvedValue("completed"),
          data: jobData,
          remove,
        }),
        add,
      },
      registry: { get: vi.fn().mockReturnValue({ timeoutMs: 60_000 }) },
    } as unknown as RouteDeps;

    await handleRetryJob(res, "completed-job", deps);

    expect(remove).toHaveBeenCalled();
    expect(add).toHaveBeenCalledWith(
      "renovate-triage",
      expect.objectContaining({ dispatch_state: "pending" }),
      expect.objectContaining({ jobId: "completed-job" })
    );
    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).retried).toBe(true);
  });

  it("re-queues failed job", async () => {
    const res = mockRes();
    const remove = vi.fn().mockResolvedValue(undefined);
    const add = vi.fn().mockResolvedValue(undefined);
    const jobData = { role: "renovate-triage", repo: "org/repo", priority: 1 };
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          getState: vi.fn().mockResolvedValue("failed"),
          data: jobData,
          remove,
        }),
        add,
      },
      registry: { get: vi.fn().mockReturnValue({ timeoutMs: 60_000 }) },
    } as unknown as RouteDeps;

    await handleRetryJob(res, "failed-job", deps);

    expect(remove).toHaveBeenCalled();
    expect(add).toHaveBeenCalled();
    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).retried).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// handleResetCircuit
// ---------------------------------------------------------------------------

describe("handleResetCircuit", () => {
  it("returns 200 reset:true when circuit was open", async () => {
    const res = mockRes();
    const reset = vi.fn().mockResolvedValue(true);
    const deps = {
      circuitBreaker: { reset },
    } as unknown as RouteDeps;

    await handleResetCircuit(res, "org/repo", deps);

    expect(reset).toHaveBeenCalledWith("org/repo");
    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).reset).toBe(true);
  });

  it("returns 200 reset:false when circuit was already closed", async () => {
    const res = mockRes();
    const reset = vi.fn().mockResolvedValue(false);
    const deps = {
      circuitBreaker: { reset },
    } as unknown as RouteDeps;

    await handleResetCircuit(res, "org/other-repo", deps);

    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).reset).toBe(false);
  });

  it("URL-decodes the repo parameter", async () => {
    const res = mockRes();
    const reset = vi.fn().mockResolvedValue(true);
    const deps = {
      circuitBreaker: { reset },
    } as unknown as RouteDeps;

    // Simulate a URL-encoded repo name (the server decodes before calling this handler)
    await handleResetCircuit(res, "org/my repo", deps);

    expect(reset).toHaveBeenCalledWith("org/my repo");
  });
});
