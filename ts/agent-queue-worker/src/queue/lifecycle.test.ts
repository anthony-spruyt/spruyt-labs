import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/** Signal/process events registered by setupLifecycle that must be cleaned up. */
const LIFECYCLE_PROCESS_EVENTS = [
  "SIGTERM",
  "SIGINT",
  "uncaughtException",
  "unhandledRejection",
] as const;

function removeLifecycleListeners(): void {
  for (const event of LIFECYCLE_PROCESS_EVENTS) {
    process.removeAllListeners(event);
  }
}

import type { Config } from "../config.js";
import { type LifecycleDeps, setupLifecycle } from "./lifecycle.js";

vi.mock("../github.js", () => ({
  fetchReposWithRevertLabels: vi.fn().mockResolvedValue(new Map()),
}));

vi.mock("../logger.js", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
    error: vi.fn(),
  },
}));

vi.mock("../metrics.js", () => ({
  queueDepth: { set: vi.fn() },
  jobFailures: { inc: vi.fn() },
  jobExhausted: { inc: vi.fn() },
  workerShutdowns: { inc: vi.fn() },
  dedupActionCounter: { inc: vi.fn() },
}));

const mockConfig = {
  PORT: 3000,
  GITHUB_OWNER: "org",
  GITHUB_TOKEN: "tok",
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

function createMockDeps() {
  const worker = new EventEmitter();
  const pipelineExec = vi.fn().mockResolvedValue([]);
  const pipeline = vi.fn().mockReturnValue({
    set: vi.fn().mockReturnThis(),
    exec: pipelineExec,
  });
  const redis = {
    pipeline,
    get: vi.fn(),
    set: vi.fn(),
    rpush: vi.fn(),
    ltrim: vi.fn(),
    expire: vi.fn(),
    quit: vi.fn(),
  };
  const queue = {
    add: vi.fn(),
    close: vi.fn(),
    getWaitingCount: vi.fn().mockResolvedValue(0),
    getJobCountByTypes: vi.fn().mockResolvedValue(0),
  };
  const server = {
    listen: vi.fn((_port: number, cb: () => void) => cb()),
    close: vi.fn((cb: () => void) => cb()),
  };
  const drainBuffer = vi.fn().mockResolvedValue({
    role: "sre-alert",
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    data: { fingerprint: "fp-1" },
  });
  const registry = {
    get: vi.fn().mockReturnValue({
      timeoutMs: 900_000,
      cooldownMs: 300_000,
      jobOptions: { attempts: 1 },
      bufferKey: (id: string) => `agent:sre-alerts:${id}`,
      drainBuffer,
    }),
  };

  return {
    worker,
    queue,
    redis,
    server,
    registry,
    drainBuffer,
    pipeline,
    pipelineExec,
    deps: {
      worker,
      queue,
      redis,
      processor: { cancelAll: vi.fn() },
      registry,
      circuitBreaker: { trip: vi.fn() },
      healthGate: { check: vi.fn(), clear: vi.fn(), setWorker: vi.fn() },
      server,
      config: mockConfig,
    } as unknown as LifecycleDeps,
  };
}

describe("lifecycle error handlers", () => {
  let mocks: ReturnType<typeof createMockDeps>;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks = createMockDeps();
    setupLifecycle(mocks.deps);
  });

  afterEach(() => {
    removeLifecycleListeners();
  });

  it("logs BullMQ worker errors without crashing", async () => {
    const { logger } = await import("../logger.js");

    mocks.worker.emit("error", new Error("Redis connection lost"));

    expect(logger.error).toHaveBeenCalledWith("BullMQ worker error", {
      error: "Error: Redis connection lost",
    });
  });
});

describe("lifecycle triaged marker writes", () => {
  let mocks: ReturnType<typeof createMockDeps>;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks = createMockDeps();
    setupLifecycle(mocks.deps);
  });

  afterEach(() => {
    removeLifecycleListeners();
  });

  it("writes triaged marker for job fingerprint", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.pipeline).toHaveBeenCalled();
    });

    const pipe = mocks.pipeline.mock.results[0]?.value;
    expect(pipe.set).toHaveBeenCalledWith(
      "agent:sre-triaged:org/repo:fp-1",
      "1",
      "EX",
      3600
    );
    expect(mocks.pipelineExec).toHaveBeenCalled();
  });

  it("writes markers for fingerprints in alerts array", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-main",
          alerts: [{ fingerprint: "fp-a1" }, { fingerprint: "fp-a2" }],
        },
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.pipeline).toHaveBeenCalled();
    });

    const pipe = mocks.pipeline.mock.results[0]?.value;
    expect(pipe.set).toHaveBeenCalledTimes(3);
    expect(pipe.set).toHaveBeenCalledWith(
      "agent:sre-triaged:org/repo:fp-main",
      "1",
      "EX",
      3600
    );
    expect(pipe.set).toHaveBeenCalledWith(
      "agent:sre-triaged:org/repo:fp-a1",
      "1",
      "EX",
      3600
    );
    expect(pipe.set).toHaveBeenCalledWith(
      "agent:sre-triaged:org/repo:fp-a2",
      "1",
      "EX",
      3600
    );
  });

  it("uses per-job triage_suppress_s override", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-1",
          triage_suppress_s: 7200,
        },
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.pipeline).toHaveBeenCalled();
    });

    const pipe = mocks.pipeline.mock.results[0]?.value;
    expect(pipe.set).toHaveBeenCalledWith(
      "agent:sre-triaged:org/repo:fp-1",
      "1",
      "EX",
      7200
    );
  });

  it("skips marker writes for non-alert jobs", async () => {
    const job = {
      id: "org/repo--sre-health-check--d1",
      data: {
        role: "sre-health-check",
        repo: "org/repo",
        event_type: "schedule",
        priority: 5,
        data: { dedup_key: "d1" },
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await new Promise((r) => setTimeout(r, 50));

    expect(mocks.pipeline).not.toHaveBeenCalled();
  });

  it("deduplicates fingerprints across job and alerts", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-dup",
          alerts: [{ fingerprint: "fp-dup" }, { fingerprint: "fp-unique" }],
        },
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.pipeline).toHaveBeenCalled();
    });

    const pipe = mocks.pipeline.mock.results[0]?.value;
    expect(pipe.set).toHaveBeenCalledTimes(2);
  });

  it("logs error and skips when registry.get throws for unknown role", async () => {
    mocks.registry.get.mockImplementation(() => {
      throw new Error("Unknown role: bad");
    });
    const { logger } = await import("../logger.js");

    const job = {
      id: "org/repo--bad-job",
      data: {
        role: "bad",
        repo: "org/repo",
        event_type: "unknown",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(logger.error).toHaveBeenCalledWith(
        "Unknown role in completed job",
        expect.objectContaining({
          jobId: "org/repo--bad-job",
          role: "bad",
        })
      );
    });

    expect(mocks.drainBuffer).not.toHaveBeenCalled();
  });

  it("skips re-enqueue when all buffered alerts have suppressed fingerprints", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: {
        fingerprint: "fp-1",
        alerts: [{ fingerprint: "fp-1" }, { fingerprint: "fp-1" }],
      },
    });

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.drainBuffer).toHaveBeenCalled();
    });

    await new Promise((r) => setTimeout(r, 50));
    expect(mocks.queue.add).not.toHaveBeenCalled();
  });

  it("re-enqueues only unsuppressed alerts from buffer", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: {
        fingerprint: "fp-1",
        alerts: [{ fingerprint: "fp-1" }, { fingerprint: "fp-new" }],
      },
    });

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.queue.add).toHaveBeenCalled();
    });

    const addCall = mocks.queue.add.mock.calls[0]!;
    const addedData = addCall[1] as Record<string, unknown>;
    const alerts = (addedData.data as Record<string, unknown>).alerts as Array<
      Record<string, unknown>
    >;
    expect(alerts).toHaveLength(1);
    expect(alerts[0]!.fingerprint).toBe("fp-new");
  });

  it("filters buffered alerts against all suppressed fingerprints including alerts array", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-main",
          alerts: [{ fingerprint: "fp-batch" }],
        },
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: {
        fingerprint: "fp-main",
        alerts: [
          { fingerprint: "fp-main" },
          { fingerprint: "fp-batch" },
          { fingerprint: "fp-unseen" },
        ],
      },
    });

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.queue.add).toHaveBeenCalled();
    });

    const addCall = mocks.queue.add.mock.calls[0]!;
    const addedData = addCall[1] as Record<string, unknown>;
    const alerts = (addedData.data as Record<string, unknown>).alerts as Array<
      Record<string, unknown>
    >;
    expect(alerts).toHaveLength(1);
    expect(alerts[0]!.fingerprint).toBe("fp-unseen");
  });

  it("preserves buffered alerts without fingerprint field through filter", async () => {
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: {
        fingerprint: "fp-1",
        alerts: [
          { fingerprint: "fp-1" },
          { labels: { alertname: "NoFingerprint" } },
        ],
      },
    });

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.queue.add).toHaveBeenCalled();
    });

    const addCall = mocks.queue.add.mock.calls[0]!;
    const addedData = addCall[1] as Record<string, unknown>;
    const alerts = (addedData.data as Record<string, unknown>).alerts as Array<
      Record<string, unknown>
    >;
    expect(alerts).toHaveLength(1);
    expect(alerts[0]!.labels).toEqual({ alertname: "NoFingerprint" });
  });

  it("swallows pipeline errors with warning", async () => {
    mocks.pipelineExec.mockRejectedValueOnce(new Error("Redis down"));
    const { logger } = await import("../logger.js");

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(logger.warn).toHaveBeenCalledWith(
        "Failed to write triaged markers",
        expect.objectContaining({ jobId: "org/repo--sre-alert" })
      );
    });
  });
});

describe("lifecycle failed handler", () => {
  let mocks: ReturnType<typeof createMockDeps>;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks = createMockDeps();
    setupLifecycle(mocks.deps);
  });

  afterEach(() => {
    removeLifecycleListeners();
  });

  it("skips processing when job is null", async () => {
    const { logger } = await import("../logger.js");
    const metrics = await import("../metrics.js");

    // Emit failed with null job — no job argument
    await mocks.worker.emit("failed", null, new Error("some error"));
    await new Promise((r) => setTimeout(r, 20));

    expect(metrics.jobExhausted.inc).not.toHaveBeenCalled();
    expect(metrics.jobFailures.inc).not.toHaveBeenCalled();
    expect(logger.error).not.toHaveBeenCalled();
  });

  it("skips circuit breaker and metrics for DelayedError", async () => {
    const { DelayedError } = await import("bullmq");
    const { logger } = await import("../logger.js");
    const metrics = await import("../metrics.js");

    const job = {
      id: "org/repo--sre-alert",
      data: { role: "sre-alert", repo: "org/repo" },
      opts: { attempts: 3 },
      attemptsMade: 1,
    };

    await mocks.worker.emit("failed", job, new DelayedError());
    await new Promise((r) => setTimeout(r, 20));

    // DelayedError is a normal re-delay, not a real failure
    expect(mocks.deps.circuitBreaker.trip).not.toHaveBeenCalled();
    expect(metrics.jobExhausted.inc).not.toHaveBeenCalled();
    expect(metrics.jobFailures.inc).not.toHaveBeenCalled();
    expect(logger.error).not.toHaveBeenCalled();
    expect(logger.warn).not.toHaveBeenCalled();
  });

  it("trips circuit breaker for non-DelayedError failures", async () => {
    const job = {
      id: "job-123",
      data: { role: "sre-alert", repo: "org/repo" },
      opts: { attempts: 3 },
      attemptsMade: 1,
    };
    const err = new Error("unexpected crash");

    await mocks.worker.emit("failed", job, err);
    await vi.waitFor(() => {
      expect(mocks.deps.circuitBreaker.trip).toHaveBeenCalledWith(
        "org/repo",
        "job-123",
        1
      );
    });
  });

  it("increments jobExhausted and logs error when attempts are exhausted", async () => {
    const { logger } = await import("../logger.js");
    const metrics = await import("../metrics.js");

    const job = {
      id: "job-exhausted",
      data: { role: "renovate-triage", repo: "org/repo" },
      opts: { attempts: 2 },
      attemptsMade: 2, // attemptsMade >= opts.attempts → exhausted
    };
    const err = new Error("terminal failure");

    await mocks.worker.emit("failed", job, err);
    await vi.waitFor(() => {
      expect(metrics.jobExhausted.inc).toHaveBeenCalledWith({
        queue: "agent-jobs",
        role: "renovate-triage",
        repo: "org/repo",
      });
    });

    expect(metrics.jobFailures.inc).not.toHaveBeenCalled();
    expect(logger.error).toHaveBeenCalledWith(
      "Job exhausted all attempts",
      expect.objectContaining({
        jobId: "job-exhausted",
        role: "renovate-triage",
        repo: "org/repo",
        error: "terminal failure",
      })
    );
  });

  it("increments jobFailures and logs warn when retries remain", async () => {
    const { logger } = await import("../logger.js");
    const metrics = await import("../metrics.js");

    const job = {
      id: "job-retry",
      data: { role: "sre-alert", repo: "org/repo" },
      opts: { attempts: 3 },
      attemptsMade: 1, // 1 < 3 → has retries left
    };
    const err = new Error("transient error");

    await mocks.worker.emit("failed", job, err);
    await vi.waitFor(() => {
      expect(metrics.jobFailures.inc).toHaveBeenCalledWith({
        queue: "agent-jobs",
        role: "sre-alert",
        reason: "job_failed",
      });
    });

    expect(metrics.jobExhausted.inc).not.toHaveBeenCalled();
    expect(logger.warn).toHaveBeenCalledWith(
      "Job failed, will retry",
      expect.objectContaining({
        jobId: "job-retry",
        role: "sre-alert",
        attempt: 1,
        error: "transient error",
      })
    );
  });

  it("uses opts.attempts default of 1 when not set — single attempt counts as exhausted", async () => {
    const metrics = await import("../metrics.js");

    const job = {
      id: "job-no-attempts",
      data: { role: "sre-alert", repo: "org/repo" },
      opts: {}, // no attempts configured → defaults to 1
      attemptsMade: 1,
    };
    const err = new Error("first and only attempt");

    await mocks.worker.emit("failed", job, err);
    await vi.waitFor(() => {
      expect(metrics.jobExhausted.inc).toHaveBeenCalled();
    });
    expect(metrics.jobFailures.inc).not.toHaveBeenCalled();
  });

  it("uses 'unknown' role when job.data.role is missing", async () => {
    const metrics = await import("../metrics.js");

    const job = {
      id: "job-no-role",
      data: { repo: "org/repo" }, // no role field
      opts: { attempts: 2 },
      attemptsMade: 1,
    };
    const err = new Error("oops");

    await mocks.worker.emit("failed", job, err);
    await vi.waitFor(() => {
      expect(metrics.jobFailures.inc).toHaveBeenCalledWith(
        expect.objectContaining({ role: "unknown" })
      );
    });
  });
});

describe("lifecycle queue depth polling", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("sets queueDepth metric as sum of waiting and prioritized counts", async () => {
    const mocks = createMockDeps();
    mocks.queue.getWaitingCount = vi.fn().mockResolvedValue(7);
    mocks.queue.getJobCountByTypes = vi.fn().mockResolvedValue(3);
    const metrics = await import("../metrics.js");

    setupLifecycle(mocks.deps);

    // Advance 15 seconds to trigger the first interval tick
    await vi.advanceTimersByTimeAsync(15_000);

    expect(metrics.queueDepth.set).toHaveBeenCalledWith(
      { queue: "agent-jobs" },
      10 // 7 + 3
    );
  });

  it("polls 'prioritized' job type specifically", async () => {
    const mocks = createMockDeps();
    setupLifecycle(mocks.deps);

    await vi.advanceTimersByTimeAsync(15_000);

    expect(mocks.queue.getJobCountByTypes).toHaveBeenCalledWith("prioritized");
  });

  it("swallows Redis errors silently without crashing", async () => {
    const mocks = createMockDeps();
    mocks.queue.getWaitingCount = vi
      .fn()
      .mockRejectedValue(new Error("Redis connection refused"));
    const { logger } = await import("../logger.js");
    const metrics = await import("../metrics.js");

    setupLifecycle(mocks.deps);

    // Advance timers and flush microtasks (the interval callback is async, so
    // we advance then drain the microtask queue via a zero-delay timer advance)
    await vi.advanceTimersByTimeAsync(15_000);
    await vi.advanceTimersByTimeAsync(0);

    // No error logged and no metric set — error is silently swallowed
    expect(metrics.queueDepth.set).not.toHaveBeenCalled();
    expect(logger.error).not.toHaveBeenCalled();
  });

  it("fires every 15 seconds, not less frequently", async () => {
    const mocks = createMockDeps();
    mocks.queue.getWaitingCount = vi.fn().mockResolvedValue(1);
    mocks.queue.getJobCountByTypes = vi.fn().mockResolvedValue(0);
    const metrics = await import("../metrics.js");

    setupLifecycle(mocks.deps);

    await vi.advanceTimersByTimeAsync(45_000);

    // Should have fired 3 times in 45 seconds
    expect(metrics.queueDepth.set).toHaveBeenCalledTimes(3);
  });
});

describe("lifecycle shutdown flow", () => {
  let mocks: ReturnType<typeof createMockDeps>;
  let originalProcessExit: typeof process.exit;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks = createMockDeps();
    // The worker is an EventEmitter; shutdown calls worker.close() so we need it
    (mocks.worker as unknown as Record<string, unknown>).close = vi
      .fn()
      .mockResolvedValue(undefined);
    // Intercept process.exit so tests don't actually exit
    originalProcessExit = process.exit;
    process.exit = vi.fn() as unknown as typeof process.exit;
    setupLifecycle(mocks.deps);
  });

  afterEach(() => {
    process.exit = originalProcessExit;
    removeLifecycleListeners();
  });

  it("calls healthGate.clear() before closing resources", async () => {
    // Capture call order
    const callOrder: string[] = [];
    (
      mocks.deps.healthGate.clear as ReturnType<typeof vi.fn>
    ).mockImplementation(() => {
      callOrder.push("healthGate.clear");
    });
    (
      mocks.deps.processor.cancelAll as ReturnType<typeof vi.fn>
    ).mockImplementation(() => {
      callOrder.push("processor.cancelAll");
    });
    mocks.queue.close = vi.fn().mockImplementation(async () => {
      callOrder.push("queue.close");
    });
    (mocks.worker as unknown as { close: ReturnType<typeof vi.fn> }).close = vi
      .fn()
      .mockImplementation(async () => {
        callOrder.push("worker.close");
      });
    mocks.redis.quit = vi.fn().mockImplementation(async () => {
      callOrder.push("redis.quit");
    });

    process.emit("SIGTERM");
    await vi.waitFor(() => {
      expect(process.exit).toHaveBeenCalledWith(0);
    });

    // healthGate.clear must be called before worker/queue/redis close
    expect(callOrder.indexOf("healthGate.clear")).toBeLessThan(
      callOrder.indexOf("worker.close")
    );
    expect(callOrder.indexOf("healthGate.clear")).toBeLessThan(
      callOrder.indexOf("queue.close")
    );
    expect(callOrder.indexOf("healthGate.clear")).toBeLessThan(
      callOrder.indexOf("redis.quit")
    );
  });

  it("calls processor.cancelAll() during shutdown", async () => {
    process.emit("SIGTERM");
    await vi.waitFor(() => {
      expect(process.exit).toHaveBeenCalledWith(0);
    });

    expect(mocks.deps.processor.cancelAll).toHaveBeenCalled();
  });

  it("closes server before worker, queue, and redis", async () => {
    const callOrder: string[] = [];
    mocks.server.close = vi.fn().mockImplementation((cb: () => void) => {
      callOrder.push("server.close");
      cb();
    });
    (mocks.worker as unknown as { close: ReturnType<typeof vi.fn> }).close = vi
      .fn()
      .mockImplementation(async () => {
        callOrder.push("worker.close");
      });
    mocks.queue.close = vi.fn().mockImplementation(async () => {
      callOrder.push("queue.close");
    });
    mocks.redis.quit = vi.fn().mockImplementation(async () => {
      callOrder.push("redis.quit");
    });

    process.emit("SIGTERM");
    await vi.waitFor(() => {
      expect(process.exit).toHaveBeenCalledWith(0);
    });

    expect(callOrder.indexOf("server.close")).toBeLessThan(
      callOrder.indexOf("worker.close")
    );
    expect(callOrder.indexOf("server.close")).toBeLessThan(
      callOrder.indexOf("queue.close")
    );
    expect(callOrder.indexOf("server.close")).toBeLessThan(
      callOrder.indexOf("redis.quit")
    );
  });

  it("closes worker before queue and queue before redis", async () => {
    const callOrder: string[] = [];
    (mocks.worker as unknown as { close: ReturnType<typeof vi.fn> }).close = vi
      .fn()
      .mockImplementation(async () => {
        callOrder.push("worker.close");
      });
    mocks.queue.close = vi.fn().mockImplementation(async () => {
      callOrder.push("queue.close");
    });
    mocks.redis.quit = vi.fn().mockImplementation(async () => {
      callOrder.push("redis.quit");
    });

    process.emit("SIGTERM");
    await vi.waitFor(() => {
      expect(process.exit).toHaveBeenCalledWith(0);
    });

    expect(callOrder).toEqual(["worker.close", "queue.close", "redis.quit"]);
  });

  it("increments workerShutdowns metric on SIGTERM", async () => {
    const metrics = await import("../metrics.js");

    process.emit("SIGTERM");
    await vi.waitFor(() => {
      expect(process.exit).toHaveBeenCalledWith(0);
    });

    expect(metrics.workerShutdowns.inc).toHaveBeenCalled();
  });

  it("SIGINT also triggers graceful shutdown", async () => {
    const metrics = await import("../metrics.js");

    process.emit("SIGINT");
    await vi.waitFor(() => {
      expect(process.exit).toHaveBeenCalledWith(0);
    });

    expect(metrics.workerShutdowns.inc).toHaveBeenCalled();
    expect(mocks.deps.healthGate.clear).toHaveBeenCalled();
    expect(mocks.redis.quit).toHaveBeenCalled();
  });
});

describe("lifecycle startup reconciliation", () => {
  let mocks: ReturnType<typeof createMockDeps>;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks = createMockDeps();
  });

  it("writes revert depths to Redis for each repo returned", async () => {
    const { fetchReposWithRevertLabels } = await import("../github.js");
    vi.mocked(fetchReposWithRevertLabels).mockResolvedValueOnce(
      new Map([
        ["org/repo-a", 3],
        ["org/repo-b", 1],
      ])
    );

    setupLifecycle(mocks.deps);

    await vi.waitFor(() => {
      expect(mocks.redis.set).toHaveBeenCalledWith(
        "agent:revert-depth:org/repo-a",
        "3",
        "EX",
        3600
      );
    });

    expect(mocks.redis.set).toHaveBeenCalledWith(
      "agent:revert-depth:org/repo-b",
      "1",
      "EX",
      3600
    );
  });

  it("calls fetchReposWithRevertLabels with config owner and token", async () => {
    const { fetchReposWithRevertLabels } = await import("../github.js");

    setupLifecycle(mocks.deps);

    await vi.waitFor(() => {
      expect(fetchReposWithRevertLabels).toHaveBeenCalledWith("org", "tok");
    });
  });

  it("writes no Redis keys when no repos have revert labels", async () => {
    const { fetchReposWithRevertLabels } = await import("../github.js");
    vi.mocked(fetchReposWithRevertLabels).mockResolvedValueOnce(new Map());

    setupLifecycle(mocks.deps);

    await new Promise((r) => setTimeout(r, 50));
    expect(mocks.redis.set).not.toHaveBeenCalled();
  });

  it("logs warn and continues when fetchReposWithRevertLabels throws", async () => {
    const { fetchReposWithRevertLabels } = await import("../github.js");
    const { logger } = await import("../logger.js");
    vi.mocked(fetchReposWithRevertLabels).mockRejectedValueOnce(
      new Error("GitHub API timeout")
    );

    // Should not throw
    setupLifecycle(mocks.deps);

    await vi.waitFor(() => {
      expect(logger.warn).toHaveBeenCalledWith(
        "Startup reconciliation failed — proceeding without",
        expect.objectContaining({ error: "Error: GitHub API timeout" })
      );
    });

    // Redis should not have been written to at all
    expect(mocks.redis.set).not.toHaveBeenCalled();
  });
});

describe("lifecycle SRE buffer drain edge cases", () => {
  let mocks: ReturnType<typeof createMockDeps>;

  beforeEach(() => {
    vi.clearAllMocks();
    mocks = createMockDeps();
    setupLifecycle(mocks.deps);
  });

  afterEach(() => {
    removeLifecycleListeners();
  });

  it("does not re-enqueue when drainBuffer returns empty alerts array", async () => {
    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: { alerts: [] }, // empty alerts
    });

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.drainBuffer).toHaveBeenCalled();
    });
    await new Promise((r) => setTimeout(r, 30));

    expect(mocks.queue.add).not.toHaveBeenCalled();
  });

  it("does not re-enqueue when drainBuffer returns no alerts field", async () => {
    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: {}, // no alerts key
    });

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.drainBuffer).toHaveBeenCalled();
    });
    await new Promise((r) => setTimeout(r, 30));

    expect(mocks.queue.add).not.toHaveBeenCalled();
  });

  it("re-pushes alerts to Redis buffer when queue.add fails", async () => {
    mocks.queue.add = vi.fn().mockRejectedValueOnce(new Error("Queue full"));
    const { logger } = await import("../logger.js");

    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: {
        alerts: [{ fingerprint: "fp-x" }, { fingerprint: "fp-y" }],
      },
    });

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.redis.rpush).toHaveBeenCalled();
    });

    // Verify re-push is to the correct buffer key
    expect(mocks.redis.rpush).toHaveBeenCalledWith(
      "agent:sre-alerts:org/repo--sre-alert",
      JSON.stringify({ fingerprint: "fp-x" }),
      JSON.stringify({ fingerprint: "fp-y" })
    );
    // Trim to batch max size and set expiry
    expect(mocks.redis.ltrim).toHaveBeenCalledWith(
      "agent:sre-alerts:org/repo--sre-alert",
      -50, // -SRE_BATCH_MAX_SIZE
      -1
    );
    expect(mocks.redis.expire).toHaveBeenCalledWith(
      "agent:sre-alerts:org/repo--sre-alert",
      3600
    );
    expect(logger.warn).toHaveBeenCalledWith(
      "Re-pushed alerts after failed auto-queue",
      expect.objectContaining({ jobId: "org/repo--sre-alert", alertCount: 2 })
    );
  });

  it("warns and continues when drainBuffer itself throws", async () => {
    mocks.drainBuffer.mockRejectedValueOnce(new Error("Redis read error"));
    const { logger } = await import("../logger.js");

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(logger.warn).toHaveBeenCalledWith(
        "SRE buffer drain failed",
        expect.objectContaining({
          jobId: "org/repo--sre-alert",
          error: "Error: Redis read error",
        })
      );
    });

    // Must not propagate — queue.add never called
    expect(mocks.queue.add).not.toHaveBeenCalled();
  });

  it("strips dispatch_state and dispatched_at fields before re-enqueuing", async () => {
    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      dispatch_state: "processing",
      dispatched_at: "2026-01-01T00:00:00Z",
      data: { alerts: [{ fingerprint: "fp-fresh" }] },
    });

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.queue.add).toHaveBeenCalled();
    });

    const addedData = mocks.queue.add.mock.calls[0]![1] as Record<
      string,
      unknown
    >;
    expect(addedData).not.toHaveProperty("dispatch_state");
    expect(addedData).not.toHaveProperty("dispatched_at");
  });

  it("applies roleDef.cooldownMs as delay when re-enqueuing", async () => {
    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: { alerts: [{ fingerprint: "fp-cool" }] },
    });

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.queue.add).toHaveBeenCalled();
    });

    const addOptions = mocks.queue.add.mock.calls[0]![2] as Record<
      string,
      unknown
    >;
    // Registry mock has cooldownMs: 300_000
    expect(addOptions.delay).toBe(300_000);
  });

  it("omits delay option when roleDef.cooldownMs is 0", async () => {
    // Override registry to return cooldownMs: 0
    mocks.registry.get.mockReturnValueOnce({
      timeoutMs: 900_000,
      cooldownMs: 0,
      jobOptions: { attempts: 1 },
      bufferKey: (id: string) => `agent:sre-alerts:${id}`,
      drainBuffer: mocks.drainBuffer,
    });

    mocks.drainBuffer.mockResolvedValueOnce({
      role: "sre-alert",
      repo: "org/repo",
      event_type: "alert",
      priority: 5,
      data: { alerts: [{ fingerprint: "fp-no-delay" }] },
    });

    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
      remove: vi.fn(),
    };

    await mocks.worker.emit("completed", job);
    await vi.waitFor(() => {
      expect(mocks.queue.add).toHaveBeenCalled();
    });

    const addOptions = mocks.queue.add.mock.calls[0]![2] as Record<
      string,
      unknown
    >;
    // cooldownMs === 0 → delay must NOT be present in the options
    expect(addOptions).not.toHaveProperty("delay");
  });

  it("skips re-enqueue when role has no bufferKey or drainBuffer", async () => {
    // Override registry to return a role without buffer support
    mocks.registry.get.mockReturnValueOnce({
      timeoutMs: 900_000,
      jobOptions: { attempts: 1 },
      // no bufferKey, no drainBuffer
    });

    const job = {
      id: "org/repo--renovate-triage",
      data: {
        role: "renovate-triage",
        repo: "org/repo",
        event_type: "renovate",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
    };

    await mocks.worker.emit("completed", job);
    await new Promise((r) => setTimeout(r, 30));

    expect(mocks.drainBuffer).not.toHaveBeenCalled();
    expect(mocks.queue.add).not.toHaveBeenCalled();
  });
});
