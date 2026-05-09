import { EventEmitter } from "node:events";
import { beforeEach, describe, expect, it, vi } from "vitest";
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
