import type { Config } from "../config.js";
import { getCurrentPrHead } from "../github.js";
import type { AgentJob } from "../job/schema.js";
import type { RoleDefinition, StalenessResult } from "./types.js";

export function createRenovateRole(
  roleName: string,
  timeoutMs: number
): RoleDefinition {
  return {
    timeoutMs,
    buildIdentity(repo: string, data: Record<string, unknown>): string {
      const prNumber = data.pr_number;
      if (!prNumber)
        throw new Error(`data.pr_number required for ${roleName} jobs`);
      return `${repo}--${roleName}--${prNumber}`;
    },
    async checkStaleness(
      job: AgentJob,
      config: Config
    ): Promise<StalenessResult> {
      const prNumber = job.data.pr_number as number | undefined;
      const headSha = job.data.head_sha as string | undefined;
      if (!prNumber || !headSha) return { stale: false };
      try {
        const currentHead = await getCurrentPrHead(
          job.repo,
          prNumber,
          config.GITHUB_TOKEN
        );
        if (currentHead !== headSha) {
          return { stale: true, reason: "head_sha_changed" };
        }
      } catch {
        // GitHub API failure — proceed optimistically
      }
      return { stale: false };
    },
  };
}
