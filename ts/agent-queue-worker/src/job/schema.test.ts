import { describe, expect, it } from "vitest";
import {
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
} from "./schema.js";
import type { AgentJob } from "./schema.js";

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  payload: {},
};

describe("AgentJobSchema", () => {
  it("accepts valid triage job", () => {
    const result = AgentJobSchema.safeParse({
      ...base,
      pr_number: 42,
    });
    expect(result.success).toBe(true);
  });

  it("accepts all valid roles", () => {
    for (const role of ["triage", "fix", "validate", "execute", "sre"]) {
      const result = AgentJobSchema.safeParse({ ...base, role });
      expect(result.success).toBe(true);
    }
  });

  it("rejects invalid role", () => {
    const result = AgentJobSchema.safeParse({ ...base, role: "nope" });
    expect(result.success).toBe(false);
  });

  it("rejects empty repo", () => {
    const result = AgentJobSchema.safeParse({ ...base, repo: "" });
    expect(result.success).toBe(false);
  });

  it("rejects repo containing --", () => {
    const result = AgentJobSchema.safeParse({ ...base, repo: "org--repo" });
    expect(result.success).toBe(false);
  });

  it("rejects non-integer priority", () => {
    const result = AgentJobSchema.safeParse({ ...base, priority: 1.5 });
    expect(result.success).toBe(false);
  });

  it("accepts optional fields missing", () => {
    const result = AgentJobSchema.safeParse(base);
    expect(result.success).toBe(true);
  });

  it("accepts head_sha as optional", () => {
    const result = AgentJobSchema.safeParse(base);
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.head_sha).toBeUndefined();
    }
  });

  it("accepts head_sha when provided", () => {
    const result = AgentJobSchema.safeParse({ ...base, head_sha: "abc123" });
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.head_sha).toBe("abc123");
    }
  });

  it("accepts dedup_key", () => {
    const result = AgentJobSchema.safeParse({
      ...base,
      dedup_key: "2026-05-01",
    });
    expect(result.success).toBe(true);
  });

  it("rejects empty dedup_key", () => {
    const result = AgentJobSchema.safeParse({ ...base, dedup_key: "" });
    expect(result.success).toBe(false);
  });

  it("accepts dispatch_state values", () => {
    for (const state of ["pending", "dispatched", "failed"]) {
      const result = AgentJobSchema.safeParse({
        ...base,
        dispatch_state: state,
      });
      expect(result.success).toBe(true);
    }
  });
});

describe("DoneRequestSchema", () => {
  it("accepts valid request", () => {
    const result = DoneRequestSchema.safeParse({
      result: { status: "ok" },
      session_token: "00000000-0000-0000-0000-000000000000",
      attempt: 0,
      dispatched_at: "2026-01-01T00:00:00Z",
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid uuid", () => {
    const result = DoneRequestSchema.safeParse({
      result: {},
      session_token: "not-a-uuid",
      attempt: 0,
      dispatched_at: "2026-01-01T00:00:00Z",
    });
    expect(result.success).toBe(false);
  });

  it("rejects negative attempt", () => {
    const result = DoneRequestSchema.safeParse({
      result: {},
      session_token: "00000000-0000-0000-0000-000000000000",
      attempt: -1,
      dispatched_at: "2026-01-01T00:00:00Z",
    });
    expect(result.success).toBe(false);
  });
});

describe("FailRequestSchema", () => {
  it("accepts valid reason", () => {
    const result = FailRequestSchema.safeParse({ reason: "timeout" });
    expect(result.success).toBe(true);
  });

  it("rejects empty reason", () => {
    const result = FailRequestSchema.safeParse({ reason: "" });
    expect(result.success).toBe(false);
  });
});
