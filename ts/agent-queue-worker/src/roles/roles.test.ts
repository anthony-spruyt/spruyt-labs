import { describe, expect, it } from "vitest";
import { createDefaultRegistry } from "./registry.js";
import type { AgentJob } from "../job/schema.js";
import type { JobState } from "./types.js";

const registry = createDefaultRegistry();

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  payload: {},
};

describe("onDuplicate strategies", () => {
  describe("triage (PR role)", () => {
    it("uses default (no onDuplicate defined)", () => {
      const def = registry.get("triage");
      expect(def.onDuplicate).toBeUndefined();
    });
  });

  describe("fix (PR role)", () => {
    it("uses default (no onDuplicate defined)", () => {
      const def = registry.get("fix");
      expect(def.onDuplicate).toBeUndefined();
    });
  });

  describe("validate", () => {
    it("uses default (no onDuplicate defined)", () => {
      const def = registry.get("validate");
      expect(def.onDuplicate).toBeUndefined();
    });
  });

  describe("execute", () => {
    const def = registry.get("execute");

    it("always discards for waiting state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "execute", issue_number: 1 },
        { ...base, role: "execute", issue_number: 1 },
        "waiting"
      );
      expect(result).toEqual({ action: "discard" });
    });

    it("always discards for active state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "execute", issue_number: 1 },
        { ...base, role: "execute", issue_number: 1 },
        "active"
      );
      expect(result).toEqual({ action: "discard" });
    });

    it("always discards for prioritized state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "execute", issue_number: 1 },
        { ...base, role: "execute", issue_number: 1 },
        "prioritized"
      );
      expect(result).toEqual({ action: "discard" });
    });
  });

  describe("sre", () => {
    const def = registry.get("sre");

    it("buffers alert for waiting state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "sre", payload: { trigger: "alert" } },
        { ...base, role: "sre", payload: { trigger: "alert" } },
        "waiting"
      );
      expect(result).toEqual({ action: "buffer" });
    });

    it("buffers alert for active state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "sre", payload: { trigger: "alert" } },
        { ...base, role: "sre", payload: { trigger: "alert" } },
        "active"
      );
      expect(result).toEqual({ action: "buffer" });
    });

    it("buffers alert for prioritized state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "sre", payload: { trigger: "alert" } },
        { ...base, role: "sre", payload: { trigger: "alert" } },
        "prioritized"
      );
      expect(result).toEqual({ action: "buffer" });
    });

    it("replaces scheduled for waiting state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "sre", dedup_key: "d1" },
        { ...base, role: "sre", dedup_key: "d1" },
        "waiting"
      );
      expect(result).toEqual({ action: "replace" });
    });

    it("discards scheduled for active state", () => {
      const result = def.onDuplicate!(
        { ...base, role: "sre", dedup_key: "d1" },
        { ...base, role: "sre", dedup_key: "d1" },
        "active"
      );
      expect(result).toEqual({ action: "discard" });
    });

    it("provides bufferKey", () => {
      expect(def.bufferKey!("org/repo--sre-triage")).toBe(
        "agent:sre-alerts:org/repo--sre-triage"
      );
    });
  });
});

describe("role timeouts", () => {
  const cases: [string, number][] = [
    ["triage", 600_000],
    ["fix", 1_800_000],
    ["validate", 1_800_000],
    ["execute", 3_600_000],
    ["sre", 900_000],
  ];

  for (const [role, expected] of cases) {
    it(`${role} timeout is ${expected}ms`, () => {
      expect(registry.get(role).timeoutMs).toBe(expected);
    });
  }
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
