import { describe, expect, it } from "vitest";
import { buildJobIdentity, extractRole } from "./identity.js";
import { createDefaultRegistry } from "../roles/registry.js";
import type { AgentJob } from "./schema.js";

const registry = createDefaultRegistry();

const base: AgentJob = {
  role: "triage",
  repo: "org/repo",
  event_type: "pull_request",
  payload: {},
};

describe("buildJobIdentity", () => {
  it("builds triage identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "triage", pr_number: 42 },
      registry
    );
    expect(id.jobId).toBe("org/repo--triage--42");
    expect(id.role).toBe("triage");
    expect(id.repo).toBe("org/repo");
  });

  it("builds fix identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "fix", pr_number: 10 },
      registry
    );
    expect(id.jobId).toBe("org/repo--fix--10");
  });

  it("builds fix revert identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "fix", payload: { revert: true } },
      registry
    );
    expect(id.jobId).toBe("org/repo--fix--revert");
  });

  it("builds validate identity", () => {
    const id = buildJobIdentity({ ...base, role: "validate" }, registry);
    expect(id.jobId).toBe("org/repo--validate");
  });

  it("builds execute identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "execute", issue_number: 99 },
      registry
    );
    expect(id.jobId).toBe("org/repo--execute--99");
  });

  it("throws for execute without issue_number", () => {
    expect(() =>
      buildJobIdentity({ ...base, role: "execute" }, registry)
    ).toThrow("issue_number required");
  });

  it("builds sre alert triage identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "sre", payload: { trigger: "alert" } },
      registry
    );
    expect(id.jobId).toBe("org/repo--sre-triage");
  });

  it("builds sre scheduled identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "sre", dedup_key: "2026-05-01" },
      registry
    );
    expect(id.jobId).toBe("org/repo--sre-health-check--2026-05-01");
  });

  it("throws for sre scheduled without dedup_key", () => {
    expect(() => buildJobIdentity({ ...base, role: "sre" }, registry)).toThrow(
      "dedup_key required"
    );
  });

  it("throws for triage without pr_number", () => {
    expect(() =>
      buildJobIdentity({ ...base, role: "triage" }, registry)
    ).toThrow("pr_number required");
  });

  it("throws for unknown role", () => {
    expect(() =>
      buildJobIdentity({ ...base, role: "nope" as AgentJob["role"] }, registry)
    ).toThrow("Unknown role");
  });
});

describe("extractRole", () => {
  it("extracts role from triage job id", () => {
    expect(extractRole("org/repo--triage--42")).toBe("triage");
  });

  it("extracts role from fix job id", () => {
    expect(extractRole("org/repo--fix--10")).toBe("fix");
  });

  it("extracts role from fix revert job id", () => {
    expect(extractRole("org/repo--fix--revert")).toBe("fix");
  });

  it("extracts role from validate job id", () => {
    expect(extractRole("org/repo--validate")).toBe("validate");
  });

  it("extracts role from execute job id", () => {
    expect(extractRole("org/repo--execute--99")).toBe("execute");
  });

  it("extracts role from sre alert job id", () => {
    expect(extractRole("org/repo--sre-triage")).toBe("sre-triage");
  });

  it("extracts role from sre scheduled job id", () => {
    expect(extractRole("org/repo--sre-health-check--2026-05-01")).toBe(
      "sre-health-check"
    );
  });

  it("returns unknown for malformed id", () => {
    expect(extractRole("nope")).toBe("unknown");
  });
});

describe("extractRole round-trip with buildJobIdentity", () => {
  const cases: { desc: string; job: AgentJob; expectedSegment: string }[] = [
    {
      desc: "triage",
      job: { ...base, role: "triage", pr_number: 42 },
      expectedSegment: "triage",
    },
    {
      desc: "fix",
      job: { ...base, role: "fix", pr_number: 10 },
      expectedSegment: "fix",
    },
    {
      desc: "fix revert",
      job: { ...base, role: "fix", payload: { revert: true } },
      expectedSegment: "fix",
    },
    {
      desc: "validate",
      job: { ...base, role: "validate" },
      expectedSegment: "validate",
    },
    {
      desc: "execute",
      job: { ...base, role: "execute", issue_number: 99 },
      expectedSegment: "execute",
    },
    {
      desc: "sre alert",
      job: { ...base, role: "sre", payload: { trigger: "alert" } },
      expectedSegment: "sre-triage",
    },
    {
      desc: "sre scheduled",
      job: { ...base, role: "sre", dedup_key: "2026-05-01" },
      expectedSegment: "sre-health-check",
    },
  ];

  for (const { desc, job, expectedSegment } of cases) {
    it(`${desc}: extractRole recovers segment from buildJobIdentity output`, () => {
      const identity = buildJobIdentity(job, registry);
      expect(extractRole(identity.jobId)).toBe(expectedSegment);
    });
  }
});
