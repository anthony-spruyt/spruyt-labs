import type { RoleDefinition, StalenessResult } from "./types.js";
import type { AgentJob } from "../job/schema.js";
import { getCurrentPrHead } from "../github.js";
import type { Config } from "../config.js";

export function createPrRole(
  roleName: string,
  timeoutMs: number
): RoleDefinition {
  return {
    timeoutMs,
    buildIdentitySegments(job: AgentJob): string[] {
      if (roleName === "fix" && job.payload?.revert) {
        return [job.repo, "fix", "revert"];
      }
      if (!job.pr_number)
        throw new Error(`pr_number required for ${roleName} jobs`);
      return [job.repo, roleName, String(job.pr_number)];
    },
    async checkStaleness(
      job: AgentJob,
      config: Config
    ): Promise<StalenessResult> {
      if (!job.pr_number || !job.head_sha) return { stale: false };
      try {
        const currentHead = await getCurrentPrHead(
          job.repo,
          job.pr_number,
          config.GITHUB_TOKEN
        );
        if (currentHead !== job.head_sha) {
          return { stale: true, reason: "head_sha_changed" };
        }
      } catch {
        // GitHub API failure — proceed optimistically
      }
      return { stale: false };
    },
  };
}
