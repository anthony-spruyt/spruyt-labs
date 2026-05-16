import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DelayedError } from "bullmq";
import type { Config } from "./config.js";
import { checkDependencies, clearRecoveryPoll } from "./health.js";

const baseConfig = {
  HEALTH_CHECK_TIMEOUT_MS: 2000,
  HEALTH_POLL_INTERVAL_MS: 100,
  HEALTH_MAX_PAUSE_MS: 500,
  N8N_HEALTH_URL: "http://n8n.test/healthz/readiness",
  LITELLM_HEALTH_URL: "http://litellm.test/health/readiness",
} as Config;

function createMockWorker() {
  return {
    pause: vi.fn().mockResolvedValue(undefined),
    resume: vi.fn(),
  };
}

function createMockJob(id = "job-1") {
  return {
    id,
    token: "tok-1",
    moveToDelayed: vi.fn().mockResolvedValue(undefined),
  };
}

describe("checkDependencies", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    clearRecoveryPoll();
  });

  afterEach(() => {
    clearRecoveryPoll();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("returns immediately when both endpoints are healthy", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    const worker = createMockWorker();
    const job = createMockJob();

    await checkDependencies(baseConfig, worker as any, job as any);

    expect(worker.pause).not.toHaveBeenCalled();
    expect(job.moveToDelayed).not.toHaveBeenCalled();
  });

  it("throws DelayedError when n8n is down", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockImplementation((url: string) =>
          url.includes("n8n")
            ? Promise.reject(new Error("ECONNREFUSED"))
            : Promise.resolve({ ok: true })
        )
    );
    const worker = createMockWorker();
    const job = createMockJob();

    await expect(
      checkDependencies(baseConfig, worker as any, job as any)
    ).rejects.toThrow(DelayedError);

    expect(job.moveToDelayed).toHaveBeenCalledOnce();
    expect(worker.pause).toHaveBeenCalledOnce();
  });

  it("throws DelayedError when litellm is down", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockImplementation((url: string) =>
          url.includes("litellm")
            ? Promise.resolve({ ok: false, status: 503 })
            : Promise.resolve({ ok: true })
        )
    );
    const worker = createMockWorker();
    const job = createMockJob();

    await expect(
      checkDependencies(baseConfig, worker as any, job as any)
    ).rejects.toThrow(DelayedError);

    expect(job.moveToDelayed).toHaveBeenCalledOnce();
    expect(worker.pause).toHaveBeenCalledOnce();
  });

  it("does not start duplicate recovery polls", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );
    const worker = createMockWorker();
    const job1 = createMockJob("job-1");
    const job2 = createMockJob("job-2");

    await expect(
      checkDependencies(baseConfig, worker as any, job1 as any)
    ).rejects.toThrow(DelayedError);
    await expect(
      checkDependencies(baseConfig, worker as any, job2 as any)
    ).rejects.toThrow(DelayedError);

    // pause called twice (once per job), but only one recovery poll
    expect(worker.pause).toHaveBeenCalledTimes(2);
    // Both jobs delayed
    expect(job1.moveToDelayed).toHaveBeenCalledOnce();
    expect(job2.moveToDelayed).toHaveBeenCalledOnce();
  });

  it("resumes worker when deps recover", async () => {
    let callCount = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() => {
        callCount++;
        // First 2 calls (initial check): fail. After that: succeed.
        if (callCount <= 2) return Promise.reject(new Error("down"));
        return Promise.resolve({ ok: true });
      })
    );
    const worker = createMockWorker();
    const job = createMockJob();

    await expect(
      checkDependencies(baseConfig, worker as any, job as any)
    ).rejects.toThrow(DelayedError);

    // Advance past one poll interval to trigger recovery
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS + 10);

    expect(worker.resume).toHaveBeenCalledOnce();
  });

  it("resumes worker after max pause duration exceeded", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("permanently down"))
    );
    const worker = createMockWorker();
    const job = createMockJob();

    await expect(
      checkDependencies(baseConfig, worker as any, job as any)
    ).rejects.toThrow(DelayedError);

    // Advance past max pause
    await vi.advanceTimersByTimeAsync(
      baseConfig.HEALTH_MAX_PAUSE_MS + baseConfig.HEALTH_POLL_INTERVAL_MS + 10
    );

    expect(worker.resume).toHaveBeenCalledOnce();
  });

  it("clearRecoveryPoll stops the poll", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("down")));
    const worker = createMockWorker();
    const job = createMockJob();

    await expect(
      checkDependencies(baseConfig, worker as any, job as any)
    ).rejects.toThrow(DelayedError);

    clearRecoveryPoll();

    // Advance time — resume should NOT be called (poll cleared)
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_MAX_PAUSE_MS * 2);
    expect(worker.resume).not.toHaveBeenCalled();
  });
});
