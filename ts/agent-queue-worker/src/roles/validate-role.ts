import type { RoleDefinition } from "./types.js";

export const validateRole: RoleDefinition = {
  timeoutMs: 3_600_000,
  buildIdentity(repo: string, _data: Record<string, unknown>): string {
    return `${repo}--validate`;
  },
};
