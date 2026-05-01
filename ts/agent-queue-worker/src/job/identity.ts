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

// Returns the registry role name, not the raw identity segment.
// e.g. "org/repo--sre-triage" → "sre", not "sre-triage".
export function extractRole(jobId: string, registry: RoleRegistry): string {
  const parts = jobId.split("--");
  const segment = parts[1];
  if (!segment) return "unknown";

  if (registry.has(segment)) return segment;

  // Compound segments like "sre-triage" or "sre-health-check": find the
  // registry key that is a prefix of the segment.
  for (const name of registry.names()) {
    if (segment.startsWith(`${name}-`)) return name;
  }

  return "unknown";
}
