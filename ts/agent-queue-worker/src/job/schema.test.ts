import { describe, expect, it } from "vitest";
import {
  AgentJobInputSchema,
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
  VALID_ROLES,
} from "./schema.js";

describe("AgentJobInputSchema", () => {
  const triageBase = {
    role: "renovate-triage",
    repo: "org/repo",
    event_type: "pull_request",
    priority: 5,
    data: { pr_number: 42, head_sha: "abc123" },
  };

  it("accepts valid renovate-triage job", () => {
    const result = AgentJobInputSchema.safeParse(triageBase);
    expect(result.success).toBe(true);
  });

  it("rejects renovate-triage without data.pr_number", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      data: { head_sha: "abc123" },
    });
    expect(result.success).toBe(false);
  });

  it("rejects renovate-triage without data.head_sha", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      data: { pr_number: 42 },
    });
    expect(result.success).toBe(false);
  });

  it("allows extra keys in renovate-triage data (n8n metadata passthrough)", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      data: { pr_number: 42, head_sha: "abc123", extra: "ok" },
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid renovate-fix job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "renovate-fix",
    });
    expect(result.success).toBe(true);
  });

  it("rejects renovate-fix without data.pr_number", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "renovate-fix",
      data: { head_sha: "abc123" },
    });
    expect(result.success).toBe(false);
  });

  it("accepts valid execute-issue job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "execute-issue",
      data: { issue_number: 99 },
    });
    expect(result.success).toBe(true);
  });

  it("rejects execute-issue without data.issue_number", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "execute-issue",
      data: {},
    });
    expect(result.success).toBe(false);
  });

  it("allows extra keys in execute-issue data (n8n metadata passthrough)", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "execute-issue",
      data: { issue_number: 99, extra: "ok" },
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid sre-alert job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-alert",
      data: {
        fingerprint: "fp-abc",
        alertname: "HighCPU",
        severity: "warning",
      },
    });
    expect(result.success).toBe(true);
  });

  it("rejects sre-alert without data.fingerprint", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-alert",
      data: { alertname: "HighCPU" },
    });
    expect(result.success).toBe(false);
  });

  it("allows extra keys in sre-alert data (AlertManager passthrough)", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-alert",
      data: {
        fingerprint: "fp-abc",
        alertname: "HighCPU",
        labels: { pod: "x" },
      },
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid sre-health-check job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-health-check",
      data: { dedup_key: "2026-05-01" },
    });
    expect(result.success).toBe(true);
  });

  it("rejects sre-health-check without data.dedup_key", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-health-check",
      data: {},
    });
    expect(result.success).toBe(false);
  });

  it("allows extra keys in sre-health-check data (n8n metadata passthrough)", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-health-check",
      data: {
        dedup_key: "2026-05-01",
        metaData: { workflowId: "abc", executionId: "123" },
      },
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid revert job with any data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "revert",
      data: { reason: "ci_failed" },
    });
    expect(result.success).toBe(true);
  });

  it("accepts revert with empty data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "revert",
      data: {},
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid validate job with any data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "validate",
      data: { commit_sha: "abc" },
    });
    expect(result.success).toBe(true);
  });

  it("accepts validate with empty data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "validate",
      data: {},
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid role", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "nope",
    });
    expect(result.success).toBe(false);
  });

  it("rejects empty repo", () => {
    const result = AgentJobInputSchema.safeParse({ ...triageBase, repo: "" });
    expect(result.success).toBe(false);
  });

  it("rejects repo containing --", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      repo: "org--repo",
    });
    expect(result.success).toBe(false);
  });

  it("rejects non-integer priority", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      priority: 1.5,
    });
    expect(result.success).toBe(false);
  });

  it("rejects missing priority", () => {
    const { priority: _, ...noPriority } = triageBase;
    const result = AgentJobInputSchema.safeParse(noPriority);
    expect(result.success).toBe(false);
  });

  it("rejects missing data", () => {
    const { data: _, ...noData } = triageBase;
    const result = AgentJobInputSchema.safeParse(noData);
    expect(result.success).toBe(false);
  });

  it("strips dispatch_state from input", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      dispatch_state: "dispatched",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dispatch_state" in result.data).toBe(false);
    }
  });

  it("strips dispatched_at from input", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      dispatched_at: "2026-01-01T00:00:00Z",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dispatched_at" in result.data).toBe(false);
    }
  });

  it("has correct VALID_ROLES list", () => {
    expect([...VALID_ROLES].sort()).toEqual([
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

describe("AgentJobSchema (internal)", () => {
  const base = {
    role: "renovate-triage",
    repo: "org/repo",
    event_type: "pull_request",
    priority: 5,
    data: { pr_number: 42, head_sha: "abc123" },
  };

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

  it("accepts any data shape (internal schema is permissive)", () => {
    const result = AgentJobSchema.safeParse({
      ...base,
      data: { pr_number: 42, head_sha: "abc", extra: "ok-internally" },
    });
    expect(result.success).toBe(true);
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
    const result = DoneRequestSchema.safeParse({ result: { status: "ok" } });
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
