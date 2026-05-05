import type { RoleRegistry } from "../roles/registry.js";
import type { AgentJob } from "./schema.js";

export interface JobIdentity {
  jobId: string;
  role: string;
  repo: string;
}

export function buildJobIdentity(
  job: AgentJob,
  registry: RoleRegistry
): JobIdentity {
  const roleDef = registry.get(job.role);
  const jobId = roleDef.buildIdentity(job.repo, job.data);
  return {
    jobId,
    role: job.role,
    repo: job.repo,
  };
}

export function extractRole(jobId: string, registry: RoleRegistry): string {
  const firstSep = jobId.indexOf("--");
  if (firstSep === -1) return "unknown";
  const afterRepo = jobId.substring(firstSep + 2);

  for (const name of registry.names()) {
    if (afterRepo === name || afterRepo.startsWith(`${name}--`)) {
      return name;
    }
  }

  return "unknown";
}
