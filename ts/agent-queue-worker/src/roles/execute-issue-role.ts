import type { AgentJob } from "../job/schema.js";
import type { DuplicateAction, JobState, RoleDefinition } from "./types.js";

export const executeIssueRole: RoleDefinition = {
  timeoutMs: 10_800_000,
  buildIdentity(repo: string, data: Record<string, unknown>): string {
    const issueNumber = data.issue_number;
    if (!issueNumber)
      throw new Error("data.issue_number required for execute-issue jobs");
    return `${repo}--execute-issue--${issueNumber}`;
  },
  onDuplicate(
    _existing: AgentJob,
    _incoming: AgentJob,
    _state: JobState
  ): DuplicateAction {
    return { action: "discard" };
  },
};
