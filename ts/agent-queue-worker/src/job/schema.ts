import { z } from "zod";

export const VALID_ROLES = [
  "renovate-triage",
  "renovate-fix",
  "revert",
  "execute-issue",
  "sre-alert",
  "sre-health-check",
  "validate",
] as const;
export type Role = (typeof VALID_ROLES)[number];

const envelope = {
  repo: z
    .string()
    .min(1)
    .refine((r) => !r.includes("--"), "repo must not contain --"),
  priority: z.number().int().min(1),
  event_type: z.string().min(1),
};

const renovateData = z.looseObject({
  pr_number: z.number().int().positive(),
  head_sha: z.string().min(1),
});

const executeIssueData = z.looseObject({
  issue_number: z.number().int().positive(),
});

const sreAlertData = z.looseObject({ fingerprint: z.string().min(1) });

const sreHealthCheckData = z.looseObject({
  dedup_key: z.string().min(1),
});

const openData = z.record(z.string(), z.unknown());

export const AgentJobInputSchema = z.discriminatedUnion("role", [
  z.object({
    role: z.literal("renovate-triage"),
    ...envelope,
    data: renovateData,
  }),
  z.object({
    role: z.literal("renovate-fix"),
    ...envelope,
    data: renovateData,
  }),
  z.object({ role: z.literal("revert"), ...envelope, data: openData }),
  z.object({
    role: z.literal("execute-issue"),
    ...envelope,
    data: executeIssueData,
  }),
  z.object({ role: z.literal("sre-alert"), ...envelope, data: sreAlertData }),
  z.object({
    role: z.literal("sre-health-check"),
    ...envelope,
    data: sreHealthCheckData,
  }),
  z.object({ role: z.literal("validate"), ...envelope, data: openData }),
]);

export type AgentJobInput = z.infer<typeof AgentJobInputSchema>;

export const AgentJobSchema = z.object({
  role: z.enum(VALID_ROLES),
  ...envelope,
  data: z.record(z.string(), z.unknown()),
  dispatched_at: z.string().optional(),
  dispatch_state: z.enum(["pending", "dispatched", "failed"]).optional(),
});

export type AgentJob = z.infer<typeof AgentJobSchema>;

export function toAgentJob(input: AgentJobInput): AgentJob {
  return input as AgentJob;
}

export const DoneRequestSchema = z.object({
  result: z.record(z.string(), z.unknown()),
  session_token: z.string().uuid(),
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
