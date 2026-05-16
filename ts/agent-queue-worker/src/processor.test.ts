import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DelayedError } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "./config.js";
import type { RoleRegistry } from "./roles/registry.js";
import { Processor } from "./processor.js";

vi.mock("./health.js", () => ({
  checkDependencies: vi.fn().mockResolvedValue(undefined),
}));

import { checkDependencies } from "./health.js";

const mockRedis = {
  set: vi.fn().mockResolvedValue("OK"),
  get: vi.fn().mockResolvedValue(null),
  del: vi.fn().mockResolvedValue(1),
  exists: vi.fn().mockResolvedValue(0),
} as unknown as Redis;

const baseConfig = {
  N8N_DISPATCH_WEBHOOK: "http://n8n.test.svc/webhook/dispatch",
  WORKER_TO_N8N_SECRET: "test",
} as Config;

const mockRoleDef = {
  timeoutMs: 60_000,
};

const mockRegistry = {
  get: vi.fn().mockReturnValue(mockRoleDef),
} as unknown as RoleRegistry;

function createMockJob(id = "job-1") {
  return {
    id,
    data: {
      role: "renovate-triage",
      repo: "org/repo",
      dispatch_state: "pending",
    },
    attemptsMade: 0,
    token: "tok-1",
    opts: { attempts: 3 },
    extendLock: vi.fn().mockResolvedValue(undefined),
    updateData: vi.fn().mockResolvedValue(undefined),
    moveToDelayed: vi.fn().mockResolvedValue(undefined),
  };
}

function createMockWorker() {
  return {
    pause: vi.fn().mockResolvedValue(undefined),
    resume: vi.fn(),
  };
}

describe("Processor.process", () => {
  let processor: Processor;

  beforeEach(() => {
    vi.clearAllMocks();
    processor = new Processor(mockRedis, baseConfig, mockRegistry);
    processor.setWorker(createMockWorker() as any);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("cleans up agent:active when checkDependencies throws DelayedError", async () => {
    vi.mocked(checkDependencies).mockRejectedValueOnce(new DelayedError());

    await expect(processor.process(createMockJob() as any)).rejects.toThrow(
      DelayedError
    );

    expect(mockRedis.del).toHaveBeenCalledWith(
      "agent:active:job-1",
      "agent:session:job-1"
    );
  });

  it("does not start timers when checkDependencies throws DelayedError", async () => {
    vi.useFakeTimers();
    const job = createMockJob();
    vi.mocked(checkDependencies).mockRejectedValueOnce(new DelayedError());

    await expect(processor.process(job as any)).rejects.toThrow(DelayedError);

    // If timers were started, advancing would trigger lock extension
    await vi.advanceTimersByTimeAsync(35_000);
    expect(job.extendLock).not.toHaveBeenCalled();

    vi.useRealTimers();
  });

  it("cleans up agent:active on normal early return (cached result)", async () => {
    vi.mocked(mockRedis.get).mockResolvedValueOnce(
      JSON.stringify({ status: "ok" })
    );

    const result = await processor.process(createMockJob() as any);

    expect(result.status).toBe("ok");
    expect(mockRedis.del).toHaveBeenCalledWith(
      "agent:active:job-1",
      "agent:session:job-1"
    );
  });

  it("returns duplicate without cleanup when lock fails", async () => {
    vi.mocked(mockRedis.set).mockResolvedValueOnce(null);

    const result = await processor.process(createMockJob() as any);

    expect(result.status).toBe("duplicate");
    // del should NOT be called — duplicate exits before outer try
    expect(mockRedis.del).not.toHaveBeenCalled();
  });
});
