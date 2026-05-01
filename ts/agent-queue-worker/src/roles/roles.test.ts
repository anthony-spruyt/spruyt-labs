import { describe, expect, it } from "vitest";
import { createDefaultRegistry } from "./registry.js";
import { resolveDuplicateAction } from "./types.js";
import type { AgentJob } from "../job/schema.js";
import type { JobState } from "./types.js";

const registry = createDefaultRegistry();

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  payload: {},
};

const STATES: JobState[] = ["waiting", "prioritized", "active"];

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
  });

  describe("sre bufferKey", () => {
    it("provides bufferKey", () => {
      const def = registry.get("sre");
      expect(def.bufferKey!("org/repo--sre-triage")).toBe(
        "agent:sre-alerts:org/repo--sre-triage"
      );
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
