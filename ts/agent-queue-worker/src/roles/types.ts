import type { Redis } from "ioredis";
import type { AgentJob } from "../job/schema.js";
import type { Config } from "../config.js";

export type DuplicateAction =
  | { action: "replace" }
  | { action: "buffer" }
  | { action: "discard" };

export type JobState = "waiting" | "prioritized" | "active";

export type StalenessResult =
  | { stale: false }
  | { stale: true; reason: string };

export interface RoleDefinition {
  readonly timeoutMs: number;
  buildIdentitySegments(job: AgentJob): string[];
  checkStaleness?(job: AgentJob, config: Config): Promise<StalenessResult>;
  onDuplicate?(
    existingData: AgentJob,
    incomingRequest: AgentJob,
    state: JobState
  ): DuplicateAction;
  bufferKey?(jobId: string): string;
  drainBuffer?(jobId: string, data: AgentJob, redis: Redis): Promise<AgentJob>;
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
