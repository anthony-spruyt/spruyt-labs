import type { RoleDefinition } from "./types.js";

export const revertRole: RoleDefinition = {
  timeoutMs: 1_800_000,
  buildIdentity(repo: string, _data: Record<string, unknown>): string {
    return `${repo}--revert`;
  },
};
