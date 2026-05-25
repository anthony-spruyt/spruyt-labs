import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fetchReposWithRevertLabels, getCurrentPrHead } from "./github.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeFetchOk(body: unknown): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: true,
    json: () => Promise.resolve(body),
  }) as unknown as typeof fetch;
}

function makeFetchFail(status: number): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok: false,
    status,
    json: () => Promise.resolve({}),
  }) as unknown as typeof fetch;
}

// ---------------------------------------------------------------------------
// getCurrentPrHead
// ---------------------------------------------------------------------------

describe("getCurrentPrHead", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("returns head SHA from a successful response", async () => {
    vi.stubGlobal("fetch", makeFetchOk({ head: { sha: "abc123" } }));

    const sha = await getCurrentPrHead("org/repo", 42);

    expect(sha).toBe("abc123");
  });

  it("calls the correct GitHub REST endpoint", async () => {
    const fetchMock = makeFetchOk({ head: { sha: "deadbeef" } });
    vi.stubGlobal("fetch", fetchMock);

    await getCurrentPrHead("myorg/myrepo", 7);

    const [url] = (fetchMock as ReturnType<typeof vi.fn>).mock.calls[0] as [
      string,
      RequestInit,
    ];
    expect(url).toBe("https://api.github.com/repos/myorg/myrepo/pulls/7");
  });

  it("sets Accept and User-Agent headers without a token", async () => {
    const fetchMock = makeFetchOk({ head: { sha: "abc" } });
    vi.stubGlobal("fetch", fetchMock);

    await getCurrentPrHead("org/repo", 1);

    const [, init] = (fetchMock as ReturnType<typeof vi.fn>).mock.calls[0] as [
      string,
      RequestInit,
    ];
    const headers = init.headers as Record<string, string>;
    expect(headers.Accept).toBe("application/vnd.github.v3+json");
    expect(headers["User-Agent"]).toBe("agent-queue-worker");
    expect(headers.Authorization).toBeUndefined();
  });

  it("adds Authorization header when token is provided", async () => {
    const fetchMock = makeFetchOk({ head: { sha: "abc" } });
    vi.stubGlobal("fetch", fetchMock);

    await getCurrentPrHead("org/repo", 1, "ghp_TOKEN");

    const [, init] = (fetchMock as ReturnType<typeof vi.fn>).mock.calls[0] as [
      string,
      RequestInit,
    ];
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBe("Bearer ghp_TOKEN");
  });

  it("throws when GitHub API returns a non-ok status", async () => {
    vi.stubGlobal("fetch", makeFetchFail(404));

    await expect(getCurrentPrHead("org/repo", 99)).rejects.toThrow(
      "GitHub API 404"
    );
  });

  it("throws when GitHub API returns 403", async () => {
    vi.stubGlobal("fetch", makeFetchFail(403));

    await expect(getCurrentPrHead("org/repo", 1, "bad-token")).rejects.toThrow(
      "GitHub API 403"
    );
  });

  it("throws when fetch itself rejects (network error)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockRejectedValue(new TypeError("fetch failed"))
    );

    await expect(getCurrentPrHead("org/repo", 1)).rejects.toThrow(
      "fetch failed"
    );
  });

  it("propagates JSON parse errors when response body is malformed", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () => Promise.reject(new SyntaxError("Unexpected token")),
      })
    );

    await expect(getCurrentPrHead("org/repo", 1)).rejects.toThrow(
      "Unexpected token"
    );
  });
});

// ---------------------------------------------------------------------------
// fetchReposWithRevertLabels
// ---------------------------------------------------------------------------

describe("fetchReposWithRevertLabels", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it("returns an empty map when owner has no repos", async () => {
    // fetchPublicRepos returns [] on the first call → loop exits immediately
    vi.stubGlobal("fetch", makeFetchOk([]));

    const result = await fetchReposWithRevertLabels("emptyowner");

    expect(result.size).toBe(0);
  });

  it("returns an empty map when no repos have revert labels", async () => {
    // Page 1: one repo, partial page (< 100) → no more pages
    // countRevertLabels: zero issues
    const fetchMock = vi
      .fn()
      // fetchPublicRepos page 1
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([{ full_name: "owner/repo-a" }]),
      })
      // countRevertLabels for owner/repo-a — all issues older than 1 hour
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve([
            { created_at: new Date(Date.now() - 7_200_000).toISOString() },
          ]),
      });
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchReposWithRevertLabels("owner");

    expect(result.size).toBe(0);
  });

  it("includes repos whose revert-labeled issues were created within the last hour", async () => {
    const fetchMock = vi
      .fn()
      // fetchPublicRepos page 1
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve([
            { full_name: "owner/repo-a" },
            { full_name: "owner/repo-b" },
          ]),
      })
      // countRevertLabels for owner/repo-a — 2 recent issues
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve([
            { created_at: new Date(Date.now() - 1_000).toISOString() },
            { created_at: new Date(Date.now() - 5_000).toISOString() },
          ]),
      })
      // countRevertLabels for owner/repo-b — no recent issues
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([]),
      });
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchReposWithRevertLabels("owner");

    expect(result.size).toBe(1);
    expect(result.get("owner/repo-a")).toBe(2);
    expect(result.has("owner/repo-b")).toBe(false);
  });

  it("skips repos when countRevertLabels throws, continuing with others", async () => {
    const fetchMock = vi
      .fn()
      // fetchPublicRepos page 1
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve([
            { full_name: "owner/repo-bad" },
            { full_name: "owner/repo-good" },
          ]),
      })
      // countRevertLabels for owner/repo-bad — network error (non-ok → returns 0 without throw)
      // Actually countRevertLabels returns 0 on non-ok; to cause a throw we simulate json() failing
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.reject(new Error("parse error")),
      })
      // countRevertLabels for owner/repo-good — 1 recent issue
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve([
            { created_at: new Date(Date.now() - 100).toISOString() },
          ]),
      });
    vi.stubGlobal("fetch", fetchMock);

    // Should not throw; bad repo is skipped
    const result = await fetchReposWithRevertLabels("owner");

    expect(result.has("owner/repo-bad")).toBe(false);
    expect(result.get("owner/repo-good")).toBe(1);
  });

  it("throws when fetchPublicRepos returns a non-ok response", async () => {
    vi.stubGlobal("fetch", makeFetchFail(401));

    await expect(
      fetchReposWithRevertLabels("owner", "bad-token")
    ).rejects.toThrow("GitHub API 401");
  });

  it("passes the token to both repo list and label count requests", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([{ full_name: "owner/repo-a" }]),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([]),
      });
    vi.stubGlobal("fetch", fetchMock);

    await fetchReposWithRevertLabels("owner", "mytoken");

    const allCalls = (fetchMock as ReturnType<typeof vi.fn>).mock.calls as [
      string,
      RequestInit,
    ][];
    for (const [, init] of allCalls) {
      const headers = init.headers as Record<string, string>;
      expect(headers.Authorization).toBe("Bearer mytoken");
    }
  });

  it("paginates until a partial page is returned", async () => {
    // fetchPublicRepos fetches ALL pages before returning, so the call order is:
    //   1. GET repos page 1 (100 items → triggers page 2)
    //   2. GET repos page 2 (1 item → partial page, stop)
    //   3. GET countRevertLabels for each of the 101 repos
    const fullPage = Array.from({ length: 100 }, (_, i) => ({
      full_name: `owner/repo-${i}`,
    }));
    const partialPage = [{ full_name: "owner/repo-extra" }];

    const fetchMock = vi.fn();
    // Page 1 repos
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(fullPage),
    });
    // Page 2 repos (partial → terminates pagination)
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: () => Promise.resolve(partialPage),
    });
    // countRevertLabels for all 100 repos from page 1 — return 0 issues each
    for (let i = 0; i < 100; i++) {
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([]),
      });
    }
    // countRevertLabels for the extra repo (page 2) — 1 recent issue
    fetchMock.mockResolvedValueOnce({
      ok: true,
      json: () =>
        Promise.resolve([
          { created_at: new Date(Date.now() - 60_000).toISOString() },
        ]),
    });

    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchReposWithRevertLabels("owner");

    expect(result.get("owner/repo-extra")).toBe(1);
  });

  it("countRevertLabels returns 0 when issues endpoint returns non-ok", async () => {
    const fetchMock = vi
      .fn()
      // fetchPublicRepos
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([{ full_name: "owner/repo-a" }]),
      })
      // countRevertLabels returns non-ok → count treated as 0
      .mockResolvedValueOnce({
        ok: false,
        status: 403,
      });
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchReposWithRevertLabels("owner");

    expect(result.size).toBe(0);
  });

  it("only counts issues created within the last hour", async () => {
    const now = Date.now();
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: () => Promise.resolve([{ full_name: "owner/repo-a" }]),
      })
      .mockResolvedValueOnce({
        ok: true,
        json: () =>
          Promise.resolve([
            // recent — within 1 hour
            { created_at: new Date(now - 1_800_000).toISOString() },
            // old — more than 1 hour ago
            { created_at: new Date(now - 3_700_000).toISOString() },
            // borderline old (just over 1 hour)
            { created_at: new Date(now - 3_600_001).toISOString() },
          ]),
      });
    vi.stubGlobal("fetch", fetchMock);

    const result = await fetchReposWithRevertLabels("owner");

    // Only the one recent issue qualifies
    expect(result.get("owner/repo-a")).toBe(1);
  });
});
