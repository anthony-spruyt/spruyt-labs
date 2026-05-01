import type { AgentJob } from "./schema.js";
import type { RoleRegistry } from "../roles/registry.js";

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
  const segments = roleDef.buildIdentitySegments(job);
  return {
    jobId: segments.join("--"),
    role: job.role,
    repo: job.repo,
  };
}

export function extractRole(jobId: string): string {
  const parts = jobId.split("--");
  return parts[1] ?? "unknown";
}
