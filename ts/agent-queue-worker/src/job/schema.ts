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
  priority: z.number().int().min(1),
  repo: z
    .string()
    .min(1)
    .refine((r) => !r.includes("--"), "repo must not contain --"),
  event_type: z.string().min(1),
  payload: z.record(z.string(), z.unknown()),
};

const prFieldsRequired = {
  ...commonFields,
  pr_number: z.number().int().positive(),
  head_sha: z.string().min(1),
};

const prFieldsOptional = {
  ...commonFields,
  pr_number: z.number().int().positive().optional(),
  head_sha: z.string().min(1).optional(),
};

const BaseAgentJobInputSchema = z.discriminatedUnion("role", [
  z.object({ role: z.literal("triage"), ...prFieldsRequired }),
  z.object({ role: z.literal("fix"), ...prFieldsOptional }),
  z.object({ role: z.literal("validate"), ...commonFields }),
  z.object({
    role: z.literal("execute"),
    ...commonFields,
    issue_number: z.number().int().positive(),
  }),
  z.object({
    role: z.literal("sre"),
    ...commonFields,
    dedup_key: z.string().min(1).optional(),
  }),
]);

export const AgentJobInputSchema = BaseAgentJobInputSchema.superRefine(
  (data, ctx) => {
    if (data.role === "fix" && !data.payload?.revert && !data.pr_number) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "pr_number required for fix jobs unless payload.revert is set",
        path: ["pr_number"],
      });
    }
    if (
      data.role === "sre" &&
      data.payload?.trigger !== "alert" &&
      !data.dedup_key
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "dedup_key required for sre jobs unless trigger is alert",
        path: ["dedup_key"],
      });
    }
  }
);

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
