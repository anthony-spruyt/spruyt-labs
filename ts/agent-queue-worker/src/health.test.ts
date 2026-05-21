import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Config } from "./config.js";
import { HealthGate } from "./health.js";

const baseConfig = {
  HEALTH_CHECK_TIMEOUT_MS: 2000,
  HEALTH_POLL_INTERVAL_MS: 100,
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
  });

  it("waits and resumes worker when deps recover", async () => {
    let callCount = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() => {
        callCount++;
        if (callCount <= 4) return Promise.reject(new Error("down"));
        return Promise.resolve({ ok: true });
      })
    );
    const { gate, worker } = createGate();
    const job = createMockJob();

    const checkPromise = gate.check(job as any);

    // Initial check + first poll both fail (4 fetch calls), second poll succeeds
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);

    await checkPromise;

    expect(worker.pause).toHaveBeenCalledOnce();
    expect(worker.resume).toHaveBeenCalledOnce();
  });

  it("skips resume when worker is closing on recovery", async () => {
    let callCount = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() => {
        callCount++;
        if (callCount <= 4) return Promise.reject(new Error("down"));
        return Promise.resolve({ ok: true });
      })
    );
    const { gate, worker } = createGate();
    const job = createMockJob();

    const checkPromise = gate.check(job as any);
    worker.closing = true;

    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);

    await checkPromise;

    expect(worker.resume).not.toHaveBeenCalled();
  });

  it("paused is false initially", () => {
    const { gate } = createGate();
    expect(gate.paused).toBe(false);
  });

  it("paused is true while waiting for deps", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );
    const { gate } = createGate();
    const job = createMockJob();

    const checkPromise = gate.check(job as any);

    // Advance past first sleep so microtasks flush and paused flag is set
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);

    expect(gate.paused).toBe(true);

    // Now make it recover
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);

    await checkPromise;

    expect(gate.paused).toBe(false);
  });

  it("paused resets to false after clear()", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new Error("ECONNREFUSED"))
    );
    const { gate } = createGate();
    const job = createMockJob();

    const checkPromise = gate.check(job as any);

    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);

    expect(gate.paused).toBe(true);

    gate.clear();
    expect(gate.paused).toBe(false);

    // Still in loop — make it recover so promise resolves
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    await vi.advanceTimersByTimeAsync(baseConfig.HEALTH_POLL_INTERVAL_MS);
    await checkPromise;
  });

  it("throws if setWorker not called", async () => {
    const gate = new HealthGate(baseConfig);
    const job = createMockJob();

    await expect(gate.check(job as any)).rejects.toThrow(
      "HealthGate.setWorker() must be called before check()"
    );
  });
});
