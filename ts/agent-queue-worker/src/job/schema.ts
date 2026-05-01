import { z } from "zod";

export const VALID_ROLES = [
  "triage",
  "fix",
  "validate",
  "execute",
  "sre",
] as const;
export type Role = (typeof VALID_ROLES)[number];

const commonFields = {
  priority: z.number().int().min(1).optional(),
  repo: z
    .string()
    .min(1)
    .refine((r) => !r.includes("--"), "repo must not contain --"),
  event_type: z.string().min(1),
  payload: z.record(z.string(), z.unknown()),
};

const prFields = {
  ...commonFields,
  pr_number: z.number().int().positive().optional(),
  head_sha: z.string().min(1).optional(),
};

export const AgentJobInputSchema = z.discriminatedUnion("role", [
  z.object({ role: z.literal("triage"), ...prFields }),
  z.object({ role: z.literal("fix"), ...prFields }),
  z.object({ role: z.literal("validate"), ...commonFields }),
  z.object({
    role: z.literal("execute"),
    ...commonFields,
    issue_number: z.number().int().positive().optional(),
  }),
  z.object({
    role: z.literal("sre"),
    ...commonFields,
    dedup_key: z.string().min(1).optional(),
  }),
]);

export type AgentJobInput = z.infer<typeof AgentJobInputSchema>;

export const AgentJobSchema = z.object({
  role: z.enum(VALID_ROLES),
  ...commonFields,
  pr_number: z.number().int().positive().optional(),
  issue_number: z.number().int().positive().optional(),
  head_sha: z.string().min(1).optional(),
  dedup_key: z.string().min(1).optional(),
  dispatched_at: z.string().optional(),
  dispatch_state: z.enum(["pending", "dispatched", "failed"]).optional(),
});

export type AgentJob = z.infer<typeof AgentJobSchema>;

export const DoneRequestSchema = z.object({
  result: z.record(z.string(), z.unknown()),
  session_token: z.string().uuid(),
  attempt: z.number().int().min(0),
  dispatched_at: z.string(),
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
