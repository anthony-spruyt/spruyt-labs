import { logger } from "./logger.js";

export async function getCurrentPrHead(
  repo: string,
  prNumber: number,
  token?: string
): Promise<string> {
  const url = `https://api.github.com/repos/${repo}/pulls/${prNumber}`;
  const headers: Record<string, string> = {
    Accept: "application/vnd.github.v3+json",
    "User-Agent": "agent-queue-worker",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const resp = await fetch(url, {
    headers,
    signal: AbortSignal.timeout(10_000),
  });
  if (!resp.ok) throw new Error(`GitHub API ${resp.status}: ${url}`);

  const data = (await resp.json()) as { head: { sha: string } };
  return data.head.sha;
}

export async function fetchReposWithRevertLabels(
  owner: string,
  token?: string
): Promise<Map<string, number>> {
  const revertDepths = new Map<string, number>();
  const repos = await fetchPublicRepos(owner, token);

  for (const repo of repos) {
    try {
      const count = await countRevertLabels(repo, token);
      if (count > 0) {
        revertDepths.set(repo, count);
        logger.info("Reconciled revert depth from GitHub", { repo, count });
      }
    } catch (err) {
      logger.warn("Failed to check revert labels", {
        repo,
        error: String(err),
      });
    }
  }

  return revertDepths;
}

async function fetchPublicRepos(
  owner: string,
  token?: string
): Promise<string[]> {
  const repos: string[] = [];
  let page = 1;

  while (true) {
    const url = `https://api.github.com/users/${owner}/repos?type=public&per_page=100&page=${page}`;
    const headers: Record<string, string> = {
      Accept: "application/vnd.github.v3+json",
      "User-Agent": "agent-queue-worker",
    };
    if (token) headers.Authorization = `Bearer ${token}`;

    const resp = await fetch(url, {
      headers,
      signal: AbortSignal.timeout(15_000),
    });
    if (!resp.ok) throw new Error(`GitHub API ${resp.status}: ${url}`);

    const data = (await resp.json()) as { full_name: string }[];
    if (data.length === 0) break;

    repos.push(...data.map((r) => r.full_name));
    if (data.length < 100) break;
    page++;
  }

  return repos;
}

async function countRevertLabels(
  repo: string,
  token?: string
): Promise<number> {
  const url = `https://api.github.com/repos/${repo}/issues?labels=agent/revert&state=all&per_page=5&sort=created&direction=desc`;
  const headers: Record<string, string> = {
    Accept: "application/vnd.github.v3+json",
    "User-Agent": "agent-queue-worker",
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const resp = await fetch(url, {
    headers,
    signal: AbortSignal.timeout(10_000),
  });
  if (!resp.ok) return 0;

  const data = (await resp.json()) as { created_at: string }[];
  const oneHourAgo = Date.now() - 3_600_000;
  return data.filter((i) => new Date(i.created_at).getTime() > oneHourAgo)
    .length;
}
