import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DelayedError } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "./config.js";
import type { HealthGate } from "./health.js";
import type { RoleRegistry } from "./roles/registry.js";
import { Processor } from "./processor.js";

// ─── Shared factories (fresh instances per test) ──────────────────────────────

function createMockRedis() {
  return {
    set: vi.fn().mockResolvedValue("OK"),
    get: vi.fn().mockResolvedValue(null),
    del: vi.fn().mockResolvedValue(1),
    exists: vi.fn().mockResolvedValue(0),
    eval: vi.fn().mockResolvedValue("valid"),
  } as unknown as Redis;
}

const baseConfig = {
  N8N_DISPATCH_WEBHOOK: "http://n8n.test.svc/webhook/dispatch",
  WORKER_TO_N8N_SECRET: "test",
} as Config;

const defaultRoleDef = { timeoutMs: 60_000 };

function createMockRegistry(roleDef: object = defaultRoleDef) {
  return {
    get: vi.fn().mockReturnValue(roleDef),
  } as unknown as RoleRegistry;
}

function createMockHealthGate() {
  return {
    check: vi.fn().mockResolvedValue(undefined),
    clear: vi.fn(),
    setWorker: vi.fn(),
  } as unknown as HealthGate;
}

function createMockJob(
  id = "job-1",
  dataOverrides: Record<string, unknown> = {}
) {
  return {
    id,
    data: {
      role: "renovate-triage",
      repo: "org/repo",
      dispatch_state: "pending",
      ...dataOverrides,
    },
    attemptsMade: 0,
    token: "tok-1",
    opts: { attempts: 3 },
    extendLock: vi.fn().mockResolvedValue(undefined),
    updateData: vi.fn().mockResolvedValue(undefined),
    moveToDelayed: vi.fn().mockResolvedValue(undefined),
  };
}

/** Wait until a callback is registered for the given jobId, then resolve it. */
async function waitForCallbackAndResolve(
  processor: Processor,
  jobId: string,
  result: { status: string; [k: string]: unknown }
): Promise<void> {
  await vi.waitFor(
    async () => {
      const ok = await processor.resolveCallback(jobId, result);
      if (!ok) throw new Error(`callback for ${jobId} not yet registered`);
    },
    { timeout: 3000, interval: 10 }
  );
}

describe("Processor.process", () => {
  let redis: Redis;
  let processor: Processor;
  let healthGate: HealthGate;

  beforeEach(() => {
    redis = createMockRedis();
    healthGate = createMockHealthGate();
    processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      healthGate
    );
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("cleans up agent:active when health gate throws DelayedError", async () => {
    vi.mocked(healthGate.check).mockRejectedValueOnce(new DelayedError());

    await expect(processor.process(createMockJob() as any)).rejects.toThrow(
      DelayedError
    );

    expect(redis.del).toHaveBeenCalledWith(
      "agent:active:job-1",
      "agent:session:job-1"
    );
  });

  it("does not start timers when health gate throws DelayedError", async () => {
    vi.useFakeTimers();
    const job = createMockJob();
    vi.mocked(healthGate.check).mockRejectedValueOnce(new DelayedError());

    await expect(processor.process(job as any)).rejects.toThrow(DelayedError);

    await vi.advanceTimersByTimeAsync(35_000);
    expect(job.extendLock).not.toHaveBeenCalled();

    vi.useRealTimers();
  });

  it("cleans up agent:active on normal early return (cached result)", async () => {
    vi.mocked(redis.get).mockResolvedValueOnce(
      JSON.stringify({ status: "ok" })
    );

    const result = await processor.process(createMockJob() as any);

    expect(result.status).toBe("ok");
    expect(redis.del).toHaveBeenCalledWith(
      "agent:active:job-1",
      "agent:session:job-1"
    );
  });

  it("returns duplicate without cleanup when lock fails", async () => {
    vi.mocked(redis.set).mockResolvedValueOnce(null);

    const result = await processor.process(createMockJob() as any);

    expect(result.status).toBe("duplicate");
    expect(redis.del).not.toHaveBeenCalled();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// resolveCallback
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.resolveCallback", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("returns false when no callback is registered for jobId", async () => {
    const processor = new Processor(
      createMockRedis(),
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const resolved = await processor.resolveCallback("unknown-job", {
      status: "ok",
    });
    expect(resolved).toBe(false);
  });

  it("returns true and delivers result to a waiting callback", async () => {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const job = createMockJob("cb-job");
    const delivered: any[] = [];
    const processPromise = processor
      .process(job as any)
      .then((r) => delivered.push(r));

    await waitForCallbackAndResolve(processor, "cb-job", { status: "done" });
    await processPromise;

    expect(delivered[0]).toEqual({ status: "done" });
  });

  it("removes callback entry so a second call returns false", async () => {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const job = createMockJob("rc-once");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "rc-once", { status: "done" });

    const second = await processor.resolveCallback("rc-once", {
      status: "done",
    });
    expect(second).toBe(false);

    await processPromise;
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// cancelAll
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.cancelAll", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("resolves pending callbacks with cancelled so process() throws", async () => {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const job = createMockJob("cancel-single");
    const processPromise = processor.process(job as any);

    // Wait until fetch has been called — at that point awaitCallback has been
    // entered and the callback is registered in the map. This is non-destructive.
    await vi.waitFor(
      () => {
        if (fetchMock.mock.calls.length === 0)
          throw new Error("fetch not called yet");
      },
      { timeout: 3000, interval: 10 }
    );

    processor.cancelAll();

    await expect(processPromise).rejects.toThrow(
      "Job cancelled during shutdown"
    );
  });

  it("no-ops when there are no pending callbacks", () => {
    const processor = new Processor(
      createMockRedis(),
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    expect(() => processor.cancelAll()).not.toThrow();
  });

  it("after cancelAll a second resolveCallback returns false for the cancelled job", async () => {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const job = createMockJob("ca-cleanup");
    const processPromise = processor.process(job as any).catch(() => {});

    // Wait until fetch has been called — guarantees the callback is registered
    await vi.waitFor(
      () => {
        if (fetchMock.mock.calls.length === 0)
          throw new Error("fetch not called yet");
      },
      { timeout: 3000, interval: 10 }
    );

    processor.cancelAll();

    await processPromise;

    // Callback was consumed by cancelAll, second call returns false
    const second = await processor.resolveCallback("ca-cleanup", {
      status: "x",
    });
    expect(second).toBe(false);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// cacheResult
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.cacheResult", () => {
  it("constructs key from both jobId and attempt, always uses 3600s TTL", async () => {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );

    // First call: attempt 0
    await processor.cacheResult("job-alpha", 0, { status: "x" });
    expect(redis.set).toHaveBeenCalledWith(
      "agent:result:job-alpha:0",
      expect.any(String),
      "EX",
      3600
    );

    // Second call: different jobId and non-zero attempt — proves both parts are used
    await processor.cacheResult("job-beta", 3, { status: "y" });
    expect(redis.set).toHaveBeenCalledWith(
      "agent:result:job-beta:3",
      expect.any(String),
      "EX",
      3600
    );
  });

  it("JSON-serialises the full result object so it can be round-tripped", async () => {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const result = { status: "done", payload: { a: 1, b: [2, 3] } };

    await processor.cacheResult("job-serial", 1, result);

    const callArgs = vi.mocked(redis.set).mock.calls[0];
    // Verify JSON serialisation actually happened (not just toString)
    expect(JSON.parse(callArgs[1] as string)).toEqual(result);
    // And the TTL is always 3600
    expect(callArgs[2]).toBe("EX");
    expect(callArgs[3]).toBe(3600);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// validateSession — Lua script result mapping
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.validateSession", () => {
  function makeProcessor() {
    const redis = createMockRedis();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    return { redis, processor };
  }

  it("calls redis.eval with the Lua script, numkeys=1, correct session key, and token for each result variant", async () => {
    // 'valid' variant — verify key construction and all 4 positional args
    {
      const { redis, processor } = makeProcessor();
      vi.mocked(redis.eval).mockResolvedValueOnce("valid");
      const result = await processor.validateSession("job-valid", "tok-v");
      expect(result).toBe("valid");
      expect(redis.eval).toHaveBeenCalledWith(
        expect.stringContaining("redis.call"),
        1,
        "agent:session:job-valid",
        "tok-v"
      );
    }

    // 'expired_or_missing' variant
    {
      const { redis, processor } = makeProcessor();
      vi.mocked(redis.eval).mockResolvedValueOnce("expired_or_missing");
      const result = await processor.validateSession("job-expired", "tok-e");
      expect(result).toBe("expired_or_missing");
      expect(redis.eval).toHaveBeenCalledWith(
        expect.stringContaining("redis.call"),
        1,
        "agent:session:job-expired",
        "tok-e"
      );
    }

    // 'mismatch' variant
    {
      const { redis, processor } = makeProcessor();
      vi.mocked(redis.eval).mockResolvedValueOnce("mismatch");
      const result = await processor.validateSession("job-mismatch", "tok-m");
      expect(result).toBe("mismatch");
      expect(redis.eval).toHaveBeenCalledWith(
        expect.stringContaining("redis.call"),
        1,
        "agent:session:job-mismatch",
        "tok-m"
      );
    }
  });

  it("key is agent:session:<jobId> — different jobIds produce different keys", async () => {
    const { redis, processor } = makeProcessor();
    vi.mocked(redis.eval).mockResolvedValue("valid");

    await processor.validateSession("job-aaa", "t1");
    await processor.validateSession("job-bbb", "t2");

    const calls = vi.mocked(redis.eval).mock.calls;
    expect(calls[0][2]).toBe("agent:session:job-aaa");
    expect(calls[1][2]).toBe("agent:session:job-bbb");
    // token is passed as 4th arg, not baked into the key
    expect(calls[0][3]).toBe("t1");
    expect(calls[1][3]).toBe("t2");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Staleness check branch
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.process — staleness check", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("returns stale when checkStaleness reports stale=true", async () => {
    const redis = createMockRedis();
    const registry = createMockRegistry({
      timeoutMs: 60_000,
      checkStaleness: vi
        .fn()
        .mockResolvedValue({ stale: true, reason: "pr-merged" }),
    });
    const processor = new Processor(
      redis,
      baseConfig,
      registry,
      createMockHealthGate()
    );

    const result = await processor.process(createMockJob() as any);
    expect(result.status).toBe("stale");
  });

  it("proceeds when checkStaleness reports not stale", async () => {
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const registry = createMockRegistry({
      timeoutMs: 60_000,
      checkStaleness: vi.fn().mockResolvedValue({ stale: false }),
    });
    const processor = new Processor(
      redis,
      baseConfig,
      registry,
      createMockHealthGate()
    );

    const job = createMockJob("fresh-job");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "fresh-job", { status: "ok" });
    await processPromise;
  });

  it("skips staleness entirely when role has no checkStaleness", async () => {
    // defaultRoleDef has no checkStaleness
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("no-staleness-job");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "no-staleness-job", {
      status: "ok",
    });
    await processPromise;
    // No error means staleness was correctly skipped
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// dispatchAndAwaitCallback — fetch behaviours
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor — dispatchAndAwaitCallback", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("POSTs to N8N_DISPATCH_WEBHOOK with Authorization, Content-Type, and Idempotency-Key headers", async () => {
    const redis = createMockRedis();
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("dispatch-1");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "dispatch-1", { status: "ok" });
    await processPromise;

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("http://n8n.test.svc/webhook/dispatch");
    expect(options.method).toBe("POST");

    const headers = options.headers as Record<string, string>;
    expect(headers["Authorization"]).toBe("Bearer test");
    expect(headers["Content-Type"]).toBe("application/json");
    expect(headers["Idempotency-Key"]).toBe("dispatch-1:0");
  });

  it("includes job_id, session_token, dispatched_at, timeout_seconds in body", async () => {
    const redis = createMockRedis();
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("body-check");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "body-check", { status: "ok" });
    await processPromise;

    const [, options] = fetchMock.mock.calls[0] as [string, RequestInit];
    const body = JSON.parse(options.body as string);
    expect(body.job_id).toBe("body-check");
    expect(body.session_token).toBeDefined();
    expect(body.dispatched_at).toBeDefined();
    expect(body.timeout_seconds).toBe(60); // Math.ceil(60_000 / 1000)
  });

  it("stores session token in Redis before calling fetch", async () => {
    const redis = createMockRedis();
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("session-order");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "session-order", {
      status: "ok",
    });
    await processPromise;

    const setInvOrders = vi.mocked(redis.set).mock.invocationCallOrder;
    const fetchInvOrder = fetchMock.mock.invocationCallOrder[0];
    const sessionSetIdx = vi
      .mocked(redis.set)
      .mock.calls.findIndex((c) => String(c[0]).startsWith("agent:session:"));
    expect(sessionSetIdx).toBeGreaterThanOrEqual(0);
    expect(setInvOrders[sessionSetIdx]).toBeLessThan(fetchInvOrder);
  });

  it("sends Idempotency-Key as <jobId>:<attemptsMade> using the current attempt number", async () => {
    const redis = createMockRedis();
    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("idem-job");
    (job as any).attemptsMade = 3;
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "idem-job", { status: "ok" });
    await processPromise;

    const [, options] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = options.headers as Record<string, string>;
    expect(headers["Idempotency-Key"]).toBe("idem-job:3");
  });

  it("updates dispatch_state to 'failed' and throws on non-ok response", async () => {
    const redis = createMockRedis();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 503,
        statusText: "Service Unavailable",
      })
    );

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("fail-dispatch");

    await expect(processor.process(job as any)).rejects.toThrow(
      "Dispatch failed: 503 Service Unavailable"
    );

    const failedUpdate = vi
      .mocked(job.updateData)
      .mock.calls.find((c: any[]) => c[0]?.dispatch_state === "failed");
    expect(failedUpdate).toBeDefined();
  });

  it("updates dispatch_state to 'dispatched' on successful fetch", async () => {
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("dispatch-ok");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "dispatch-ok", { status: "ok" });
    await processPromise;

    const dispatchedUpdate = vi
      .mocked(job.updateData)
      .mock.calls.find((c: any[]) => c[0]?.dispatch_state === "dispatched");
    expect(dispatchedUpdate).toBeDefined();
  });

  it("calls drainBuffer and updates job data when role provides drainBuffer", async () => {
    const redis = createMockRedis();
    const drainedData = {
      role: "renovate-triage" as const,
      repo: "org/repo",
      event_type: "push",
      priority: 1,
      data: { pr_number: 42, head_sha: "abc123", extra: "buffered" },
      dispatch_state: "pending" as const,
    };
    const drainBuffer = vi.fn().mockResolvedValue(drainedData);
    const registry = createMockRegistry({ timeoutMs: 60_000, drainBuffer });

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      registry,
      createMockHealthGate()
    );
    const job = createMockJob("drain-job");
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "drain-job", { status: "ok" });
    await processPromise;

    expect(drainBuffer).toHaveBeenCalledWith("drain-job", job.data, redis);
    // job.updateData called with drained data (before dispatch_state update)
    const drainUpdate = vi
      .mocked(job.updateData)
      .mock.calls.find((c: any[]) => c[0]?.data?.extra === "buffered");
    expect(drainUpdate).toBeDefined();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Re-dispatch when dispatch_state=dispatched but session expired
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.process — re-dispatch on expired session", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("re-dispatches to webhook and checks health gate when session expired", async () => {
    const redis = createMockRedis();
    vi.mocked(redis.exists).mockResolvedValue(0); // session gone

    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const healthGate = createMockHealthGate();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      healthGate
    );

    const job = createMockJob("redispatch-job", {
      dispatch_state: "dispatched",
    });
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "redispatch-job", {
      status: "ok",
    });
    await processPromise;

    expect(healthGate.check).toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("skips health gate and fetch when session is still alive (cache poll path)", async () => {
    const redis = createMockRedis();
    vi.mocked(redis.exists).mockResolvedValue(1); // session alive

    const fetchMock = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", fetchMock);

    const healthGate = createMockHealthGate();
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      healthGate
    );

    const job = createMockJob("nodispatch-job", {
      dispatch_state: "dispatched",
    });
    const processPromise = processor.process(job as any).catch(() => {});

    await waitForCallbackAndResolve(processor, "nodispatch-job", {
      status: "resumed",
    });
    await processPromise;

    expect(healthGate.check).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// awaitCallbackWithCachePoll
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor — awaitCallbackWithCachePoll", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("resolves via cache poll when Redis returns a cached result after 2 intervals", async () => {
    vi.useFakeTimers();
    const redis = createMockRedis();
    vi.mocked(redis.exists).mockResolvedValue(1); // session alive → no re-dispatch
    vi.mocked(redis.get)
      .mockResolvedValueOnce(null) // initial cache check at process() entry
      .mockResolvedValueOnce(null) // first 15s poll: nothing yet
      .mockResolvedValue(JSON.stringify({ status: "polled" })); // second poll hit

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );

    const job = createMockJob("poll-job", { dispatch_state: "dispatched" });
    const results: any[] = [];
    const processPromise = processor
      .process(job as any)
      .then((r) => results.push(r))
      .catch(() => {});

    // First interval — nothing
    await vi.advanceTimersByTimeAsync(15_001);
    // Second interval — cache hit
    await vi.advanceTimersByTimeAsync(15_001);

    vi.useRealTimers();
    await processPromise;

    expect(results[0]?.status).toBe("polled");
  });

  it("resolves via callback when it arrives before any poll fires", async () => {
    const redis = createMockRedis();
    vi.mocked(redis.exists).mockResolvedValue(1);

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("callback-wins", {
      dispatch_state: "dispatched",
    });
    const results: any[] = [];
    const processPromise = processor
      .process(job as any)
      .then((r) => results.push(r))
      .catch(() => {});

    await waitForCallbackAndResolve(processor, "callback-wins", {
      status: "from-callback",
    });
    await processPromise;

    expect(results[0]?.status).toBe("from-callback");
  });

  it("only resolves once when poll and callback fire concurrently (guard check)", async () => {
    vi.useFakeTimers();
    const redis = createMockRedis();
    vi.mocked(redis.exists).mockResolvedValue(1);
    vi.mocked(redis.get)
      .mockResolvedValueOnce(null) // initial cache check
      .mockResolvedValue(JSON.stringify({ status: "from-poll" })); // every poll

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("double-resolve-job", {
      dispatch_state: "dispatched",
    });
    const results: any[] = [];
    const processPromise = processor
      .process(job as any)
      .then((r) => results.push(r))
      .catch(() => {});

    // Trigger poll resolution at 15s
    await vi.advanceTimersByTimeAsync(15_001);
    // Also resolve via callback concurrently — the `if (resolved) return` guard prevents double settlement
    await processor.resolveCallback("double-resolve-job", {
      status: "from-callback",
    });

    vi.useRealTimers();
    await processPromise;

    expect(results.length).toBe(1);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Timeout racing
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.process — timeout racing", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("rejects with timeout error when callback never arrives", async () => {
    vi.useFakeTimers();
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry({ timeoutMs: 5_000 }),
      createMockHealthGate()
    );

    const job = createMockJob("timeout-job");
    const resultPromise = processor.process(job as any);
    // Attach rejection handler immediately to prevent unhandled rejection warning
    resultPromise.catch(() => {});

    // Advance past the 5s timeout
    await vi.advanceTimersByTimeAsync(6_000);

    vi.useRealTimers();
    await expect(resultPromise).rejects.toThrow("timed out");
  });

  it("callback wins the race when resolved before timeout", async () => {
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("race-job");
    const resultPromise = processor.process(job as any);

    await waitForCallbackAndResolve(processor, "race-job", {
      status: "completed",
    });

    const result = await resultPromise;
    expect(result.status).toBe("completed");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Lock extension (30s interval)
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.process — lock extension", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it("extends lock at 30s with job token, then again at 60s", async () => {
    vi.useFakeTimers();
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    // Use a long timeout so the job doesn't expire before we can check both lock extensions
    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry({ timeoutMs: 120_000 }),
      createMockHealthGate()
    );
    const job = createMockJob("lock-job");
    const processPromise = processor.process(job as any).catch(() => {});

    // First 30s interval fires
    await vi.advanceTimersByTimeAsync(30_001);
    expect(job.extendLock).toHaveBeenCalledTimes(1);
    expect(job.extendLock).toHaveBeenCalledWith("tok-1", 120_000);

    // Second 30s interval fires (at 60s from start)
    await vi.advanceTimersByTimeAsync(30_001);
    expect(job.extendLock).toHaveBeenCalledTimes(2);

    // Resolve to clean up
    await processor.resolveCallback("lock-job", { status: "done" });
    vi.useRealTimers();
    await processPromise;
  });

  it("skips extendLock when job.token is missing (warns but does not throw)", async () => {
    vi.useFakeTimers();
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("no-token-job");
    (job as any).token = undefined;

    const processPromise = processor.process(job as any).catch(() => {});

    await vi.advanceTimersByTimeAsync(35_000);

    expect(job.extendLock).not.toHaveBeenCalled();

    await processor.resolveCallback("no-token-job", { status: "done" });
    vi.useRealTimers();
    await processPromise;
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Cached result branch: process() returns cached and deletes key
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.process — cached result at entry", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("returns JSON-parsed cached result and deletes the cache key", async () => {
    const redis = createMockRedis();
    vi.mocked(redis.get).mockResolvedValueOnce(
      JSON.stringify({ status: "cached-value", extra: 42 })
    );

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("cache-job");
    const result = await processor.process(job as any);

    expect(result).toEqual({ status: "cached-value", extra: 42 });
    // Cache key deleted separately from active+session cleanup
    expect(redis.del).toHaveBeenCalledWith("agent:result:cache-job:0");
    expect(redis.del).toHaveBeenCalledWith(
      "agent:active:cache-job",
      "agent:session:cache-job"
    );
  });

  it("does not call fetch when cached result is available", async () => {
    const redis = createMockRedis();
    vi.mocked(redis.get).mockResolvedValueOnce(
      JSON.stringify({ status: "from-cache" })
    );
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    await processor.process(createMockJob() as any);

    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("does not call health gate when cached result is available", async () => {
    const redis = createMockRedis();
    vi.mocked(redis.get).mockResolvedValueOnce(
      JSON.stringify({ status: "from-cache" })
    );
    const healthGate = createMockHealthGate();

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      healthGate
    );
    await processor.process(createMockJob() as any);

    expect(healthGate.check).not.toHaveBeenCalled();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Cancelled result throws
// ─────────────────────────────────────────────────────────────────────────────
describe("Processor.process — cancelled result path", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("throws 'Job cancelled during shutdown' when callback delivers status=cancelled", async () => {
    const redis = createMockRedis();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));

    const processor = new Processor(
      redis,
      baseConfig,
      createMockRegistry(),
      createMockHealthGate()
    );
    const job = createMockJob("cancel-job");
    const resultPromise = processor.process(job as any);

    await waitForCallbackAndResolve(processor, "cancel-job", {
      status: "cancelled",
    });

    await expect(resultPromise).rejects.toThrow(
      "Job cancelled during shutdown"
    );
  });
});
