import type { JobsOptions } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "../config.js";
import type { AgentJob } from "../job/schema.js";

export type DuplicateAction =
  | { action: "replace" }
  | { action: "buffer" }
  | { action: "discard" };

export type JobState = "waiting" | "prioritized" | "active" | "delayed";

export type StalenessResult =
  | { stale: false }
  | { stale: true; reason: string };

export interface RoleDefinition {
  readonly timeoutMs: number;
  readonly cooldownMs?: number;
  readonly jobOptions?: Partial<Pick<JobsOptions, "attempts" | "backoff">>;
  buildIdentity(repo: string, data: Record<string, unknown>): string;
  checkStaleness?(job: AgentJob, config: Config): Promise<StalenessResult>;
  onDuplicate?(
    existingData: AgentJob,
    incomingRequest: AgentJob,
    state: JobState
  ): DuplicateAction;
  bufferKey?(jobId: string): string;
  drainBuffer?(jobId: string, job: AgentJob, redis: Redis): Promise<AgentJob>;
  getJobDelay?(job: AgentJob): number;
}

export function resolveDuplicateAction(
  roleDef: RoleDefinition,
  existing: AgentJob,
  incoming: AgentJob,
  state: JobState
): DuplicateAction {
  if (roleDef.onDuplicate) {
    return roleDef.onDuplicate(existing, incoming, state);
  }
  return state === "waiting" || state === "prioritized"
    ? { action: "replace" }
    : { action: "discard" };
}
