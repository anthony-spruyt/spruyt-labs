import { z } from "zod";

export const VALID_ROLES = ["triage", "fix", "validate", "execute"] as const;
export type Role = (typeof VALID_ROLES)[number];

export const ROLE_TIMEOUTS: Record<Role, number> = {
  triage: 600_000,
  fix: 1_800_000,
  validate: 1_800_000,
  execute: 3_600_000,
};

export const ROLE_PRIORITIES: Record<string, number> = {
  critical: 1,
  normal: 10,
  low: 100,
};

export const AgentJobSchema = z.object({
  role: z.enum(VALID_ROLES),
  priority: z.number().int().min(1).optional(),
  repo: z.string().min(1),
  event_type: z.string().min(1),
  pr_number: z.number().int().positive().optional(),
  issue_number: z.number().int().positive().optional(),
  head_sha: z.string().min(1),
  dispatched_at: z.string().optional(),
  dispatch_state: z.enum(["pending", "dispatched", "failed"]).optional(),
  payload: z.record(z.unknown()),
});

export type AgentJob = z.infer<typeof AgentJobSchema>;

export const DoneRequestSchema = z.object({
  result: z.record(z.unknown()),
  session_token: z.string().uuid(),
  attempt: z.number().int().min(0),
  dispatched_at: z.string().optional(),
});

export type DoneRequest = z.infer<typeof DoneRequestSchema>;

export const FailRequestSchema = z.object({
  reason: z.string().min(1),
});

export type FailRequest = z.infer<typeof FailRequestSchema>;

export interface JobResult {
  status: string;
  [key: string]: unknown;
}

export function buildJobId(data: AgentJob): string {
  const { role, repo, pr_number, issue_number, head_sha } = data;
  if (role === "validate") return `${repo}:main:validate:${head_sha}`;
  if (role === "execute") {
    if (!issue_number)
      throw new Error("issue_number required for execute jobs");
    return `${repo}:${issue_number}:execute`;
  }
  if (data.payload?.revert) return `${repo}:${head_sha}:revert:fix`;
  if (!pr_number) throw new Error(`pr_number required for ${role} jobs`);
  return `${repo}:${pr_number}:${head_sha}:${role}`;
}

export function extractRole(jobId: string): string {
  const parts = jobId.split(":");
  return parts[parts.length - 1] ?? "unknown";
}
