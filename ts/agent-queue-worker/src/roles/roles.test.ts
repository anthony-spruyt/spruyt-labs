import type { Histogram } from "prom-client";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import type { AgentJob } from "../job/schema.js";
import { createDefaultRegistry } from "./registry.js";
import type { JobState } from "./types.js";
import { resolveDuplicateAction } from "./types.js";

const mockConfig = {
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);

const STATES: JobState[] = ["waiting", "prioritized", "active", "delayed"];

function makeJob(role: string, data: Record<string, unknown> = {}): AgentJob {
  return {
    role: role as AgentJob["role"],
    repo: "org/repo",
    event_type: "test",
    priority: 5,
    data,
  };
}

describe("duplicate resolution", () => {
  describe("renovate-triage (default strategy)", () => {
    const def = registry.get("renovate-triage");
    const job = makeJob("renovate-triage", {
      pr_number: 1,
      head_sha: "abc",
    });

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("replaces when prioritized", () => {
      expect(resolveDuplicateAction(def, job, job, "prioritized")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("renovate-fix (default strategy)", () => {
    const def = registry.get("renovate-fix");
    const job = makeJob("renovate-fix", {
      pr_number: 10,
      head_sha: "def",
    });

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("replaces when prioritized", () => {
      expect(resolveDuplicateAction(def, job, job, "prioritized")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("revert (default strategy)", () => {
    const def = registry.get("revert");
    const job = makeJob("revert");

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("validate (default strategy)", () => {
    const def = registry.get("validate");
    const job = makeJob("validate");

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("execute-issue (always discard)", () => {
    const def = registry.get("execute-issue");
    const job = makeJob("execute-issue", { issue_number: 1 });

    for (const state of STATES) {
      it(`discards when ${state}`, () => {
        expect(resolveDuplicateAction(def, job, job, state)).toEqual({
          action: "discard",
        });
      });
    }
  });

  describe("sre-alert (always buffer)", () => {
    const def = registry.get("sre-alert");
    const job = makeJob("sre-alert", { fingerprint: "fp-1" });

    for (const state of STATES) {
      it(`buffers when ${state}`, () => {
        expect(resolveDuplicateAction(def, job, job, state)).toEqual({
          action: "buffer",
        });
      });
    }
  });

  describe("sre-health-check (replace or discard)", () => {
    const def = registry.get("sre-health-check");
    const job = makeJob("sre-health-check", { dedup_key: "d1" });

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("replaces when prioritized", () => {
      expect(resolveDuplicateAction(def, job, job, "prioritized")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });

    it("discards when delayed", () => {
      expect(resolveDuplicateAction(def, job, job, "delayed")).toEqual({
        action: "discard",
      });
    });
  });

  describe("sre-alert bufferKey", () => {
    it("provides bufferKey", () => {
      const def = registry.get("sre-alert");
      expect(def.bufferKey!("org/repo--sre-alert")).toBe(
        "agent:sre-alerts:org/repo--sre-alert"
      );
    });
  });

  describe("sre-alert cooldown", () => {
    it("has 5-minute cooldown between sessions", () => {
      const def = registry.get("sre-alert");
      expect(def.cooldownMs).toBe(300_000);
    });
  });
});

describe("role timeouts", () => {
  it("all timeouts are positive", () => {
    for (const role of registry.names()) {
      expect(registry.get(role).timeoutMs).toBeGreaterThan(0);
    }
  });

  it("renovate-triage is fastest (ephemeral PR check)", () => {
    const triage = registry.get("renovate-triage").timeoutMs;
    for (const role of [
      "renovate-fix",
      "revert",
      "validate",
      "execute-issue",
      "sre-alert",
      "sre-health-check",
    ]) {
      expect(triage).toBeLessThanOrEqual(registry.get(role).timeoutMs);
    }
  });

  it("execute-issue has longest timeout (full pipeline)", () => {
    const execute = registry.get("execute-issue").timeoutMs;
    for (const role of [
      "renovate-triage",
      "renovate-fix",
      "validate",
      "sre-alert",
      "sre-health-check",
      "revert",
    ]) {
      expect(execute).toBeGreaterThan(registry.get(role).timeoutMs);
    }
  });
});

describe("registry", () => {
  it("throws for unknown role", () => {
    expect(() => registry.get("nope")).toThrow("Unknown role");
  });

  it("has all expected roles", () => {
    expect(registry.names().sort()).toEqual([
      "execute-issue",
      "renovate-fix",
      "renovate-triage",
      "revert",
      "sre-alert",
      "sre-health-check",
      "validate",
    ]);
  });
});

describe("sre-alert getJobDelay", () => {
  const def = registry.get("sre-alert");

  it("returns batch window from config", () => {
    const job = makeJob("sre-alert", { fingerprint: "fp-1" });
    expect(def.getJobDelay!(job)).toBe(60_000);
  });

  it("returns per-job override when present", () => {
    const job = makeJob("sre-alert", {
      fingerprint: "fp-1",
      batch_window_ms: 30_000,
    });
    expect(def.getJobDelay!(job)).toBe(30_000);
  });

  it("caps per-job override at 6 hours", () => {
    const job = makeJob("sre-alert", {
      fingerprint: "fp-1",
      batch_window_ms: 999_999_999,
    });
    expect(def.getJobDelay!(job)).toBe(21_600_000);
  });

  it("clamps negative per-job override to 0", () => {
    const job = makeJob("sre-alert", {
      fingerprint: "fp-1",
      batch_window_ms: -1,
    });
    expect(def.getJobDelay!(job)).toBe(0);
  });

  it("returns 0 when batch window is 0", () => {
    const zeroConfig = { ...mockConfig, SRE_BATCH_WINDOW_MS: 0 } as Config;
    const zeroHistogram = { observe: vi.fn() } as unknown as Histogram;
    const zeroRegistry = createDefaultRegistry(zeroConfig, zeroHistogram);
    const def2 = zeroRegistry.get("sre-alert");
    const job = makeJob("sre-alert", { fingerprint: "fp-1" });
    expect(def2.getJobDelay!(job)).toBe(0);
  });
});

describe("sre-alert cooldownMs from config", () => {
  it("reads cooldownMs from SRE_COOLDOWN_MS config", () => {
    const def = registry.get("sre-alert");
    expect(def.cooldownMs).toBe(300_000);
  });

  it("respects custom cooldown value", () => {
    const customConfig = {
      ...mockConfig,
      SRE_COOLDOWN_MS: 120_000,
    } as Config;
    const customRegistry = createDefaultRegistry(customConfig, mockHistogram);
    const def = customRegistry.get("sre-alert");
    expect(def.cooldownMs).toBe(120_000);
  });
});

describe("sre-alert drainBuffer", () => {
  const def = registry.get("sre-alert");
  const job = makeJob("sre-alert", {
    fingerprint: "fp-1",
    alertname: "HighCPU",
  });

  beforeEach(() => {
    vi.mocked(mockHistogram.observe).mockClear();
  });

  it("includes original + buffered in alerts array", async () => {
    const items = [
      JSON.stringify({ alertname: "A1" }),
      JSON.stringify({ alertname: "A2" }),
      JSON.stringify({ alertname: "A3" }),
      JSON.stringify({ alertname: "A4" }),
      JSON.stringify({ alertname: "A5" }),
    ];
    const mockRedis = { eval: vi.fn().mockResolvedValue(items) } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(6);
    expect(result.data?.alerts).toHaveLength(6);
    expect((result.data?.alerts as any[])[0]).toEqual({
      fingerprint: "fp-1",
      alertname: "HighCPU",
    });
    expect((result.data?.alerts as any[])[1]).toEqual({ alertname: "A1" });
  });

  it("returns single-element alerts array when buffer empty", async () => {
    const mockRedis = {
      eval: vi.fn().mockResolvedValue([]),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(1);
    expect(result.data?.alerts).toEqual([
      { fingerprint: "fp-1", alertname: "HighCPU" },
    ]);
  });

  it("returns single-element alerts array when buffer null", async () => {
    const mockRedis = {
      eval: vi.fn().mockResolvedValue(null),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(1);
    expect(result.data?.alerts).toEqual([
      { fingerprint: "fp-1", alertname: "HighCPU" },
    ]);
  });
});
