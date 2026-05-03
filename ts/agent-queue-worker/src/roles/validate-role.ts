import type { AgentJob } from "../job/schema.js";
import type { RoleDefinition } from "./types.js";

export const validateRole: RoleDefinition = {
  timeoutMs: 1_800_000,
  buildIdentitySegments(job: AgentJob): string[] {
    return [job.repo, "validate"];
  },
};
