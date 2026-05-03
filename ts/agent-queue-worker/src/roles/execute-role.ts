import type { AgentJob } from "../job/schema.js";
import type { DuplicateAction, JobState, RoleDefinition } from "./types.js";

export const executeRole: RoleDefinition = {
  timeoutMs: 3_600_000,
  buildIdentitySegments(job: AgentJob): string[] {
    if (!job.issue_number)
      throw new Error("issue_number required for execute jobs");
    return [job.repo, "execute", String(job.issue_number)];
  },
  onDuplicate(
    _existing: AgentJob,
    _incoming: AgentJob,
    _state: JobState
  ): DuplicateAction {
    return { action: "discard" };
  },
};
