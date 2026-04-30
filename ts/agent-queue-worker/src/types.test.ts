import { describe, expect, it } from "vitest";
import {
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
  buildJobId,
  extractRole,
} from "./types.js";
import type { AgentJob } from "./types.js";

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  head_sha: "abc123",
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

  it("rejects non-integer priority", () => {
    const result = AgentJobSchema.safeParse({ ...base, priority: 1.5 });
    expect(result.success).toBe(false);
  });

  it("accepts optional fields missing", () => {
    const result = AgentJobSchema.safeParse(base);
    expect(result.success).toBe(true);
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
      session_token: "550e8400-e29b-41d4-a716-446655440000",
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
      session_token: "550e8400-e29b-41d4-a716-446655440000",
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

describe("buildJobId", () => {
  it("builds triage job id", () => {
    expect(buildJobId({ ...base, role: "triage", pr_number: 42 })).toBe(
      "org/repo--42--abc123--triage"
    );
  });

  it("builds fix job id", () => {
    expect(buildJobId({ ...base, role: "fix", pr_number: 10 })).toBe(
      "org/repo--10--abc123--fix"
    );
  });

  it("builds validate job id", () => {
    expect(buildJobId({ ...base, role: "validate" })).toBe(
      "org/repo--main--validate--abc123"
    );
  });

  it("builds execute job id with issue_number", () => {
    expect(buildJobId({ ...base, role: "execute", issue_number: 99 })).toBe(
      "org/repo--99--execute"
    );
  });

  it("throws for execute without issue_number", () => {
    expect(() => buildJobId({ ...base, role: "execute" })).toThrow(
      "issue_number required"
    );
  });

  it("builds sre health-check job id", () => {
    expect(buildJobId({ ...base, role: "sre" })).toBe(
      "sre-health-check--scheduled--abc123"
    );
  });

  it("builds sre alert triage job id", () => {
    expect(
      buildJobId({
        ...base,
        role: "sre",
        payload: {
          trigger: "alert",
          alertname: "HighCPU",
          fingerprint: "fp123",
        },
      })
    ).toBe("sre-triage--HighCPU--fp123");
  });

  it("builds sre alert triage with defaults", () => {
    expect(
      buildJobId({
        ...base,
        role: "sre",
        payload: { trigger: "alert" },
      })
    ).toBe("sre-triage--unknown--abc123");
  });

  it("builds revert job id", () => {
    expect(buildJobId({ ...base, payload: { revert: true } })).toBe(
      "org/repo--abc123--revert--fix"
    );
  });

  it("throws for triage without pr_number", () => {
    expect(() => buildJobId({ ...base, role: "triage" })).toThrow(
      "pr_number required"
    );
  });
});

describe("extractRole", () => {
  it("extracts role from triage job id", () => {
    expect(extractRole("org/repo--42--abc123--triage")).toBe("triage");
  });

  it("extracts role from fix job id", () => {
    expect(extractRole("org/repo--10--abc123--fix")).toBe("fix");
  });

  it("extracts role from execute job id", () => {
    expect(extractRole("org/repo--99--execute")).toBe("execute");
  });

  // extractRole returns last `--` segment, which is sha for validate/sre job IDs
  it("returns last segment for validate job id", () => {
    expect(extractRole("org/repo--main--validate--abc123")).toBe("abc123");
  });
});
