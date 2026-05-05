import type { Histogram } from "prom-client";
import { describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import { createDefaultRegistry } from "../roles/registry.js";
import { buildJobIdentity, extractRole } from "./identity.js";
import type { AgentJob } from "./schema.js";

const mockConfig = {
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);

const base: AgentJob = {
  role: "renovate-triage",
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  data: {},
};

describe("buildJobIdentity", () => {
  it("builds renovate-triage identity", () => {
    const id = buildJobIdentity(
      { ...base, data: { pr_number: 42, head_sha: "abc" } },
      registry
    );
    expect(id.jobId).toBe("org/repo--renovate-triage--42");
    expect(id.role).toBe("renovate-triage");
    expect(id.repo).toBe("org/repo");
  });

  it("builds renovate-fix identity", () => {
    const id = buildJobIdentity(
      {
        ...base,
        role: "renovate-fix",
        data: { pr_number: 10, head_sha: "def" },
      },
      registry
    );
    expect(id.jobId).toBe("org/repo--renovate-fix--10");
  });

  it("builds revert identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "revert", data: {} },
      registry
    );
    expect(id.jobId).toBe("org/repo--revert");
  });

  it("builds validate identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "validate", data: {} },
      registry
    );
    expect(id.jobId).toBe("org/repo--validate");
  });

  it("builds execute-issue identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "execute-issue", data: { issue_number: 99 } },
      registry
    );
    expect(id.jobId).toBe("org/repo--execute-issue--99");
  });

  it("throws for execute-issue without data.issue_number", () => {
    expect(() =>
      buildJobIdentity({ ...base, role: "execute-issue", data: {} }, registry)
    ).toThrow("data.issue_number required");
  });

  it("builds sre-alert identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "sre-alert", data: { fingerprint: "fp-1" } },
      registry
    );
    expect(id.jobId).toBe("org/repo--sre-alert");
  });

  it("builds sre-health-check identity", () => {
    const id = buildJobIdentity(
      {
        ...base,
        role: "sre-health-check",
        data: { dedup_key: "2026-05-01" },
      },
      registry
    );
    expect(id.jobId).toBe("org/repo--sre-health-check--2026-05-01");
  });

  it("throws for sre-health-check without data.dedup_key", () => {
    expect(() =>
      buildJobIdentity(
        { ...base, role: "sre-health-check", data: {} },
        registry
      )
    ).toThrow("data.dedup_key required");
  });

  it("throws for unknown role", () => {
    expect(() =>
      buildJobIdentity({ ...base, role: "nope" as AgentJob["role"] }, registry)
    ).toThrow("Unknown role");
  });
});

describe("extractRole", () => {
  it("extracts renovate-triage from job id", () => {
    expect(extractRole("org/repo--renovate-triage--42", registry)).toBe(
      "renovate-triage"
    );
  });

  it("extracts renovate-fix from job id", () => {
    expect(extractRole("org/repo--renovate-fix--10", registry)).toBe(
      "renovate-fix"
    );
  });

  it("extracts revert from job id", () => {
    expect(extractRole("org/repo--revert", registry)).toBe("revert");
  });

  it("extracts validate from job id", () => {
    expect(extractRole("org/repo--validate", registry)).toBe("validate");
  });

  it("extracts execute-issue from job id", () => {
    expect(extractRole("org/repo--execute-issue--99", registry)).toBe(
      "execute-issue"
    );
  });

  it("extracts sre-alert from job id", () => {
    expect(extractRole("org/repo--sre-alert", registry)).toBe("sre-alert");
  });

  it("extracts sre-health-check from job id", () => {
    expect(
      extractRole("org/repo--sre-health-check--2026-05-01", registry)
    ).toBe("sre-health-check");
  });

  it("returns unknown for malformed id", () => {
    expect(extractRole("nope", registry)).toBe("unknown");
  });
});

describe("extractRole round-trip with buildJobIdentity", () => {
  const cases: { desc: string; job: AgentJob; expectedRole: string }[] = [
    {
      desc: "renovate-triage",
      job: { ...base, data: { pr_number: 42, head_sha: "abc" } },
      expectedRole: "renovate-triage",
    },
    {
      desc: "renovate-fix",
      job: {
        ...base,
        role: "renovate-fix",
        data: { pr_number: 10, head_sha: "def" },
      },
      expectedRole: "renovate-fix",
    },
    {
      desc: "revert",
      job: { ...base, role: "revert", data: {} },
      expectedRole: "revert",
    },
    {
      desc: "validate",
      job: { ...base, role: "validate", data: {} },
      expectedRole: "validate",
    },
    {
      desc: "execute-issue",
      job: { ...base, role: "execute-issue", data: { issue_number: 99 } },
      expectedRole: "execute-issue",
    },
    {
      desc: "sre-alert",
      job: { ...base, role: "sre-alert", data: { fingerprint: "fp-1" } },
      expectedRole: "sre-alert",
    },
    {
      desc: "sre-health-check",
      job: {
        ...base,
        role: "sre-health-check",
        data: { dedup_key: "2026-05-01" },
      },
      expectedRole: "sre-health-check",
    },
  ];

  for (const { desc, job, expectedRole } of cases) {
    it(`${desc}: extractRole recovers registry key from buildJobIdentity output`, () => {
      const identity = buildJobIdentity(job, registry);
      expect(extractRole(identity.jobId, registry)).toBe(expectedRole);
    });
  }
});
