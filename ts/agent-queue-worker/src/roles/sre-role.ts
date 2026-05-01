import type { RoleDefinition, DuplicateAction, JobState } from "./types.js";
import type { AgentJob } from "../job/schema.js";

export const sreRole: RoleDefinition = {
  timeoutMs: 900_000,
  buildIdentitySegments(job: AgentJob): string[] {
    if (job.payload?.trigger === "alert") {
      return [job.repo, "sre-triage"];
    }
    if (!job.dedup_key)
      throw new Error("dedup_key required for sre scheduled jobs");
    return [job.repo, "sre-health-check", job.dedup_key];
  },
  onDuplicate(
    _existing: AgentJob,
    incoming: AgentJob,
    state: JobState
  ): DuplicateAction {
    if (incoming.payload?.trigger === "alert") {
      return { action: "buffer" };
    }
    return state === "waiting" || state === "prioritized"
      ? { action: "replace" }
      : { action: "discard" };
  },
  bufferKey(jobId: string): string {
    return `agent:sre-alerts:${jobId}`;
  },
  // drainBuffer implemented in PR 2
};
