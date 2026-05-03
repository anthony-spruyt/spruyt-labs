import { beforeEach, describe, expect, it, vi } from "vitest";
import { createDefaultRegistry } from "./registry.js";
import { resolveDuplicateAction } from "./types.js";
import type { AgentJob } from "../job/schema.js";
import type { JobState } from "./types.js";
import { Histogram } from "prom-client";
import type { Config } from "../config.js";

const mockConfig = {
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  payload: {},
};

const STATES: JobState[] = ["waiting", "prioritized", "active", "delayed"];

describe("duplicate resolution", () => {
  describe("triage (default strategy)", () => {
    const def = registry.get("triage");
    const job = { ...base, role: "triage" as const, pr_number: 1 };

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

  describe("fix (default strategy)", () => {
    const def = registry.get("fix");
    const job = { ...base, role: "fix" as const, pr_number: 10 };

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

  describe("validate (default strategy)", () => {
    const def = registry.get("validate");
    const job = { ...base, role: "validate" as const };

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

  describe("execute (always discard)", () => {
    const def = registry.get("execute");
    const job = { ...base, role: "execute" as const, issue_number: 1 };

    for (const state of STATES) {
      it(`discards when ${state}`, () => {
        expect(resolveDuplicateAction(def, job, job, state)).toEqual({
          action: "discard",
        });
      });
    }
  });

  describe("sre alerts (always buffer)", () => {
    const def = registry.get("sre");
    const alert = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert" },
    };

    for (const state of STATES) {
      it(`buffers when ${state}`, () => {
        expect(resolveDuplicateAction(def, alert, alert, state)).toEqual({
          action: "buffer",
        });
      });
    }
  });

  describe("sre scheduled (replace or discard)", () => {
    const def = registry.get("sre");
    const scheduled = { ...base, role: "sre" as const, dedup_key: "d1" };

    it("replaces when waiting", () => {
      expect(
        resolveDuplicateAction(def, scheduled, scheduled, "waiting")
      ).toEqual({ action: "replace" });
    });

    it("replaces when prioritized", () => {
      expect(
        resolveDuplicateAction(def, scheduled, scheduled, "prioritized")
      ).toEqual({ action: "replace" });
    });

    it("discards when active", () => {
      expect(
        resolveDuplicateAction(def, scheduled, scheduled, "active")
      ).toEqual({ action: "discard" });
    });

    it("discards when delayed", () => {
      expect(
        resolveDuplicateAction(def, scheduled, scheduled, "delayed")
      ).toEqual({ action: "discard" });
    });
  });

  describe("sre bufferKey", () => {
    it("provides bufferKey", () => {
      const def = registry.get("sre");
      expect(def.bufferKey!("org/repo--sre-triage")).toBe(
        "agent:sre-alerts:org/repo--sre-triage"
      );
    });
  });

  describe("sre cooldown", () => {
    it("has 5-minute cooldown between sessions", () => {
      const def = registry.get("sre");
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

  it("triage is fastest (ephemeral PR check)", () => {
    const triage = registry.get("triage").timeoutMs;
    for (const role of ["fix", "validate", "execute", "sre"]) {
      expect(triage).toBeLessThan(registry.get(role).timeoutMs);
    }
  });

  it("execute has longest timeout (full pipeline)", () => {
    const execute = registry.get("execute").timeoutMs;
    for (const role of ["triage", "fix", "validate", "sre"]) {
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
      "execute",
      "fix",
      "sre",
      "triage",
      "validate",
    ]);
  });
});

describe("sre getJobDelay", () => {
  const def = registry.get("sre");

  it("returns batch window for alert trigger", () => {
    const job = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert" },
    };
    expect(def.getJobDelay!(job)).toBe(60_000);
  });

  it("returns per-job override when present", () => {
    const job = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert", batch_window_ms: 30_000 },
    };
    expect(def.getJobDelay!(job)).toBe(30_000);
  });

  it("caps per-job override at 6 hours", () => {
    const job = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert", batch_window_ms: 999_999_999 },
    };
    expect(def.getJobDelay!(job)).toBe(21_600_000);
  });

  it("returns 0 for scheduled jobs", () => {
    const job = { ...base, role: "sre" as const, dedup_key: "d1" };
    expect(def.getJobDelay!(job)).toBe(0);
  });

  it("returns 0 when batch window is 0", () => {
    const zeroConfig = { ...mockConfig, SRE_BATCH_WINDOW_MS: 0 } as Config;
    const zeroHistogram = { observe: vi.fn() } as unknown as Histogram;
    const zeroRegistry = createDefaultRegistry(zeroConfig, zeroHistogram);
    const def2 = zeroRegistry.get("sre");
    const job = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert" },
    };
    expect(def2.getJobDelay!(job)).toBe(0);
  });
});

describe("sre cooldownMs from config", () => {
  it("reads cooldownMs from SRE_COOLDOWN_MS config", () => {
    const def = registry.get("sre");
    expect(def.cooldownMs).toBe(300_000);
  });

  it("respects custom cooldown value", () => {
    const customConfig = { ...mockConfig, SRE_COOLDOWN_MS: 120_000 } as Config;
    const customRegistry = createDefaultRegistry(customConfig, mockHistogram);
    const def = customRegistry.get("sre");
    expect(def.cooldownMs).toBe(120_000);
  });
});
