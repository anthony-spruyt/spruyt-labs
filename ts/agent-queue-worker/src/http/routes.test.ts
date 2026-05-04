import { EventEmitter } from "node:events";
import type { IncomingMessage, ServerResponse } from "node:http";
import { describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import { handleAddJob, handleGetJob, type RouteDeps } from "./routes.js";

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
  role: "triage" as const,
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  payload: { action: "opened" },
  pr_number: 42,
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
    expect(body.role).toBe("triage");
    expect(body.pr_number).toBe(42);
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

describe("handleAddJob validation", () => {
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
          buildIdentitySegments: () => {
            throw new Error("pr_number required for triage jobs");
          },
        }),
      },
      config: {} as Config,
      processor: {},
      ...overrides,
    } as unknown as RouteDeps;
  }

  it("returns 400 when buildIdentitySegments throws", async () => {
    const res = mockRes();
    const req = mockReq({
      role: "triage",
      repo: "org/repo",
      event_type: "pull_request",
      priority: 5,
      payload: {},
      pr_number: 1,
      head_sha: "abc",
    });
    const deps = makeDeps();

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(400);
    expect((res._body as Record<string, unknown>).reason).toBe(
      "invalid_request"
    );
    expect((res._body as Record<string, unknown>).error).toBe(
      "pr_number required for triage jobs"
    );
  });

  it("returns 400 when registry.get throws unknown role", async () => {
    const res = mockRes();
    const req = mockReq({
      role: "triage",
      repo: "org/repo",
      event_type: "pull_request",
      priority: 5,
      payload: {},
      pr_number: 1,
      head_sha: "abc",
    });
    const deps = makeDeps({
      registry: {
        get: vi.fn().mockImplementation((name: string) => {
          if (name === "triage")
            return {
              timeoutMs: 120_000,
              buildIdentitySegments: () => ["org/repo", "triage", "1"],
            };
          throw new Error(`Unknown role: ${name}`);
        }),
      },
    });
    // Override registry.get to throw on second call (after buildJobIdentity succeeds)
    const registryGet = deps.registry.get as ReturnType<typeof vi.fn>;
    registryGet
      .mockReturnValueOnce({
        timeoutMs: 120_000,
        buildIdentitySegments: () => ["org/repo", "triage", "1"],
      })
      .mockImplementationOnce(() => {
        throw new Error("Unknown role: triage");
      });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(400);
    expect((res._body as Record<string, unknown>).error).toBe(
      "Unknown role: triage"
    );
  });
});

describe("handleAddJob suppression", () => {
  const sreAlert = {
    role: "sre" as const,
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    payload: { trigger: "alert", fingerprint: "fp-abc123" },
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
          buildIdentitySegments: () => ["org/repo", "sre-triage"],
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

  it("does not suppress non-SRE role with fingerprint", async () => {
    const res = mockRes();
    const req = mockReq({
      role: "triage",
      repo: "org/repo",
      event_type: "pull_request",
      priority: 5,
      pr_number: 1,
      head_sha: "abc",
      payload: { trigger: "alert", fingerprint: "fp-abc123" },
    });
    const deps = makeDeps({
      redis: { exists: vi.fn().mockResolvedValue(1) },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 120_000,
          jobOptions: {},
          buildIdentitySegments: () => ["org/repo", "triage-1"],
          getJobDelay: () => 0,
        }),
      },
    });

    await handleAddJob(req, res, deps);

    expect(res._status).toBe(201);
    expect((res._body as Record<string, unknown>).added).toBe(true);
  });
});
