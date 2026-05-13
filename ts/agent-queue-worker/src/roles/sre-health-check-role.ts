import type { AgentJob } from "../job/schema.js";
import type { DuplicateAction, JobState, RoleDefinition } from "./types.js";

export const sreHealthCheckRole: RoleDefinition = {
  timeoutMs: 1_800_000,
  buildIdentity(repo: string, data: Record<string, unknown>): string {
    const dedupKey = data.dedup_key;
    if (!dedupKey)
      throw new Error("data.dedup_key required for sre-health-check jobs");
    return `${repo}--sre-health-check--${dedupKey}`;
  },
  onDuplicate(
    _existing: AgentJob,
    _incoming: AgentJob,
    state: JobState
  ): DuplicateAction {
    return state === "waiting" || state === "prioritized"
      ? { action: "replace" }
      : { action: "discard" };
  },
};
