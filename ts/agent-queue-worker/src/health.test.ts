import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DelayedError } from "bullmq";
import type { Config } from "./config.js";
import { HealthGate } from "./health.js";

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
    closing: false,
  };
}

function createMockJob(id = "job-1") {
  return {
    id,
    token: "tok-1",
    moveToDelayed: vi.fn().mockResolvedValue(undefined),
  };
}

function createGate(worker = createMockWorker()) {
  const gate = new HealthGate(baseConfig);
  gate.setWorker(worker as any);
  return { gate, worker };
}

describe("HealthGate", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("returns immediately when both endpoints are healthy", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    const { gate, worker } = createGate();
    const job = createMockJob();

    await gate.check(job as any);

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
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

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
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    expect(job.moveToDelayed).toHaveBeenCalledOnce();
    expect(worker.pause).toHaveBeenCalledOnce();
  });

  it("does not start duplicate recovery polls", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );
    const { gate, worker } = createGate();
    const job1 = createMockJob("job-1");
    const job2 = createMockJob("job-2");

    await expect(gate.check(job1 as any)).rejects.toThrow(DelayedError);
    await expect(gate.check(job2 as any)).rejects.toThrow(DelayedError);

    expect(worker.pause).toHaveBeenCalledTimes(2);
    expect(job1.moveToDelayed).toHaveBeenCalledOnce();
    expect(job2.moveToDelayed).toHaveBeenCalledOnce();
  });

  it("resumes worker when deps recover", async () => {
    let callCount = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() => {
        callCount++;
        if (callCount <= 2) return Promise.reject(new Error("down"));
        return Promise.resolve({ ok: true });
      })
    );
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS + 10);

    expect(worker.resume).toHaveBeenCalledOnce();
  });

  it("resumes worker after max pause duration exceeded", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("permanently down"))
    );
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    await vi.advanceTimersByTimeAsync(
      baseConfig.HEALTH_MAX_PAUSE_MS + baseConfig.HEALTH_POLL_INTERVAL_MS + 10
    );

    expect(worker.resume).toHaveBeenCalledOnce();
  });

  it("clear() stops the recovery poll", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("down")));
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    gate.clear();

    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_MAX_PAUSE_MS * 2);
    expect(worker.resume).not.toHaveBeenCalled();
  });

  it("paused is false initially", () => {
    const { gate } = createGate();
    expect(gate.paused).toBe(false);
  });

  it("paused is true after unhealthy check", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );
    const { gate } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    expect(gate.paused).toBe(true);
  });

  it("paused resets to false after clear()", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );
    const { gate } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);
    gate.clear();

    expect(gate.paused).toBe(false);
  });

  it("throws if setWorker not called", async () => {
    const gate = new HealthGate(baseConfig);
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(
      "HealthGate.setWorker() must be called before check()"
    );
  });

  it("skips resume when worker is closing during recovery", async () => {
    let callCount = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() => {
        callCount++;
        if (callCount <= 2) return Promise.reject(new Error("down"));
        return Promise.resolve({ ok: true });
      })
    );
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    worker.closing = true;
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS + 10);

    expect(worker.resume).not.toHaveBeenCalled();
  });

  it("skips resume when worker is closing on max pause exceeded", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("permanently down"))
    );
    const { gate, worker } = createGate();
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(DelayedError);

    worker.closing = true;
    await vi.advanceTimersByTimeAsync(
      baseConfig.HEALTH_MAX_PAUSE_MS + baseConfig.HEALTH_POLL_INTERVAL_MS + 10
    );

    expect(worker.resume).not.toHaveBeenCalled();
  });
});
