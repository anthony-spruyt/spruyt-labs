import { describe, expect, it } from "vitest";
import {
  AgentJobSchema,
  AgentJobInputSchema,
  DoneRequestSchema,
  FailRequestSchema,
} from "./schema.js";
import type { AgentJob } from "./schema.js";

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  payload: {},
};

describe("AgentJobInputSchema", () => {
  it("accepts valid triage job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      pr_number: 42,
    });
    expect(result.success).toBe(true);
  });

  it("accepts all valid roles", () => {
    for (const role of ["triage", "fix", "validate", "execute", "sre"]) {
      const result = AgentJobInputSchema.safeParse({ ...base, role });
      expect(result.success).toBe(true);
    }
  });

  it("rejects invalid role", () => {
    const result = AgentJobInputSchema.safeParse({ ...base, role: "nope" });
    expect(result.success).toBe(false);
  });

  it("rejects empty repo", () => {
    const result = AgentJobInputSchema.safeParse({ ...base, repo: "" });
    expect(result.success).toBe(false);
  });

  it("rejects repo containing --", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      repo: "org--repo",
    });
    expect(result.success).toBe(false);
  });

  it("rejects non-integer priority", () => {
    const result = AgentJobInputSchema.safeParse({ ...base, priority: 1.5 });
    expect(result.success).toBe(false);
  });

  it("rejects missing priority", () => {
    const { priority: _, ...noPriority } = base;
    const result = AgentJobInputSchema.safeParse(noPriority);
    expect(result.success).toBe(false);
  });

  it("accepts optional fields missing", () => {
    const result = AgentJobInputSchema.safeParse(base);
    expect(result.success).toBe(true);
  });

  it("accepts head_sha as optional for pr roles", () => {
    const result = AgentJobInputSchema.safeParse(base);
    expect(result.success).toBe(true);
    if (result.success && result.data.role === "triage") {
      expect(result.data.head_sha).toBeUndefined();
    }
  });

  it("accepts head_sha when provided for pr roles", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      head_sha: "abc123",
    });
    expect(result.success).toBe(true);
    if (result.success && result.data.role === "triage") {
      expect(result.data.head_sha).toBe("abc123");
    }
  });

  it("strips head_sha from non-pr roles", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      role: "sre",
      head_sha: "abc123",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("head_sha" in result.data).toBe(false);
    }
  });

  it("strips pr_number from non-pr roles", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      role: "execute",
      pr_number: 42,
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("pr_number" in result.data).toBe(false);
    }
  });

  it("strips issue_number from non-execute roles", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      role: "triage",
      issue_number: 99,
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("issue_number" in result.data).toBe(false);
    }
  });

  it("accepts dedup_key for sre role", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      role: "sre",
      dedup_key: "2026-05-01",
    });
    expect(result.success).toBe(true);
  });

  it("rejects empty dedup_key for sre role", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      role: "sre",
      dedup_key: "",
    });
    expect(result.success).toBe(false);
  });

  it("strips dedup_key from non-sre roles", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      role: "triage",
      dedup_key: "2026-05-01",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dedup_key" in result.data).toBe(false);
    }
  });

  it("strips dispatched_at from input", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      dispatched_at: "2026-01-01T00:00:00Z",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dispatched_at" in result.data).toBe(false);
    }
  });

  it("strips dispatch_state from input", () => {
    const result = AgentJobInputSchema.safeParse({
      ...base,
      dispatch_state: "dispatched",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dispatch_state" in result.data).toBe(false);
    }
  });
});

describe("AgentJobSchema (internal)", () => {
  it("accepts dispatch fields", () => {
    for (const state of ["pending", "dispatched", "failed"]) {
      const result = AgentJobSchema.safeParse({
        ...base,
        dispatch_state: state,
        dispatched_at: "2026-01-01T00:00:00Z",
      });
      expect(result.success).toBe(true);
    }
  });

  it("accepts dedup_key for any role", () => {
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
});

describe("DoneRequestSchema", () => {
  it("accepts valid request", () => {
    const result = DoneRequestSchema.safeParse({
      result: { status: "ok" },
      session_token: "00000000-0000-0000-0000-000000000000",
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid uuid", () => {
    const result = DoneRequestSchema.safeParse({
      result: {},
      session_token: "not-a-uuid",
    });
    expect(result.success).toBe(false);
  });

  it("rejects missing session_token", () => {
    const result = DoneRequestSchema.safeParse({
      result: { status: "ok" },
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
