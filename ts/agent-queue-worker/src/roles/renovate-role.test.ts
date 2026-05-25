import { afterEach, describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import type { AgentJob } from "../job/schema.js";
import { createRenovateRole } from "./renovate-role.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const baseConfig = {
  GITHUB_TOKEN: "ghp_test",
} as Config;

const configNoToken = {} as Config;

function makeJob(overrides: Partial<AgentJob["data"]> = {}): AgentJob {
  return {
    role: "renovate-triage",
    repo: "org/repo",
    event_type: "pr",
    priority: 5,
    data: {
      pr_number: 42,
      head_sha: "abc123",
      ...overrides,
    },
  };
}

function stubFetchHead(sha: string): ReturnType<typeof vi.fn> {
  const mock = vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve({ head: { sha } }),
  });
  vi.stubGlobal("fetch", mock);
  return mock;
}

function stubFetchFail(status: number): void {
  vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status }));
}

function stubFetchNetworkError(): void {
  vi.stubGlobal(
    "fetch",
    vi.fn().mockRejectedValue(new TypeError("network error"))
  );
}

// ---------------------------------------------------------------------------
// buildIdentity
// ---------------------------------------------------------------------------

describe("createRenovateRole — buildIdentity", () => {
  const role = createRenovateRole("renovate-triage", 60_000);

  it("builds identity as 'repo--roleName--prNumber'", () => {
    const identity = role.buildIdentity("org/repo", { pr_number: 7 });
    expect(identity).toBe("org/repo--renovate-triage--7");
  });

  it("includes numeric pr_number verbatim", () => {
    const identity = role.buildIdentity("acme/frontend", { pr_number: 999 });
    expect(identity).toBe("acme/frontend--renovate-triage--999");
  });

  it("throws when pr_number is missing", () => {
    expect(() => role.buildIdentity("org/repo", {})).toThrow(
      "data.pr_number required for renovate-triage jobs"
    );
  });

  it("throws when pr_number is null", () => {
    expect(() => role.buildIdentity("org/repo", { pr_number: null })).toThrow(
      "data.pr_number required for renovate-triage jobs"
    );
  });

  it("throws when pr_number is 0 (falsy)", () => {
    expect(() => role.buildIdentity("org/repo", { pr_number: 0 })).toThrow(
      "data.pr_number required for renovate-triage jobs"
    );
  });

  it("uses the roleName passed to factory, not a hardcoded string", () => {
    const fixRole = createRenovateRole("renovate-fix", 120_000);
    const identity = fixRole.buildIdentity("org/repo", { pr_number: 1 });
    expect(identity).toBe("org/repo--renovate-fix--1");
  });
});

// ---------------------------------------------------------------------------
// checkStaleness
// ---------------------------------------------------------------------------

describe("createRenovateRole — checkStaleness", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns stale=false when pr_number is missing", async () => {
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: undefined, head_sha: "abc" });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: false });
  });

  it("returns stale=false when head_sha is missing", async () => {
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ head_sha: undefined });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: false });
  });

  it("returns stale=false when both pr_number and head_sha are missing", async () => {
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: undefined, head_sha: undefined });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: false });
  });

  it("returns stale=false when current head matches job head_sha", async () => {
    stubFetchHead("abc123");
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: 42, head_sha: "abc123" });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: false });
  });

  it("returns stale=true with reason when head SHA changed", async () => {
    stubFetchHead("newsha999");
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: 42, head_sha: "oldsha111" });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: true, reason: "head_sha_changed" });
  });

  it("proceeds optimistically (stale=false) when GitHub API returns non-ok", async () => {
    stubFetchFail(500);
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: 42, head_sha: "abc123" });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: false });
  });

  it("proceeds optimistically (stale=false) when fetch throws a network error", async () => {
    stubFetchNetworkError();
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: 42, head_sha: "abc123" });

    const result = await role.checkStaleness!(job, baseConfig);

    expect(result).toEqual({ stale: false });
  });

  it("passes GITHUB_TOKEN from config to the GitHub API call", async () => {
    const fetchMock = stubFetchHead("abc123");
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob();

    await role.checkStaleness!(job, baseConfig);

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBe("Bearer ghp_test");
  });

  it("omits Authorization header when config has no GITHUB_TOKEN", async () => {
    const fetchMock = stubFetchHead("abc123");
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob();

    await role.checkStaleness!(job, configNoToken);

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBeUndefined();
  });

  it("calls the correct pull request endpoint", async () => {
    const fetchMock = stubFetchHead("abc123");
    const role = createRenovateRole("renovate-triage", 60_000);
    const job = makeJob({ pr_number: 17, head_sha: "abc123" });

    await role.checkStaleness!(job, baseConfig);

    const [url] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://api.github.com/repos/org/repo/pulls/17");
  });
});

// ---------------------------------------------------------------------------
// timeoutMs
// ---------------------------------------------------------------------------

describe("createRenovateRole — timeoutMs", () => {
  it("exposes the timeoutMs passed to the factory", () => {
    const role = createRenovateRole("renovate-triage", 45_000);
    expect(role.timeoutMs).toBe(45_000);
  });

  it("exposes different timeouts for different instances", () => {
    const triage = createRenovateRole("renovate-triage", 60_000);
    const fix = createRenovateRole("renovate-fix", 120_000);
    expect(triage.timeoutMs).toBe(60_000);
    expect(fix.timeoutMs).toBe(120_000);
  });
});
