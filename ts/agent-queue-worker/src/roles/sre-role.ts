import type { Redis } from "ioredis";
import type { RoleDefinition, DuplicateAction, JobState } from "./types.js";
import type { AgentJob } from "../job/schema.js";

// Atomic drain: LRANGE all items then DEL key in one round-trip.
// Uses Redis EVAL command (server-side Lua execution), not JavaScript eval().
const DRAIN_BUFFER_LUA = `
local items = redis.call('LRANGE', KEYS[1], 0, -1)
redis.call('DEL', KEYS[1])
return items
`;

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
  async drainBuffer(
    jobId: string,
    data: AgentJob,
    redis: Redis
  ): Promise<AgentJob> {
    const bufKey = `agent:sre-alerts:${jobId}`;
    // Redis EVAL runs Lua server-side for atomic drain
    const items = (await redis.eval(DRAIN_BUFFER_LUA, 1, bufKey)) as string[];
    if (!items || items.length === 0) return data;
    const alerts = items.map((i) => JSON.parse(i) as Record<string, unknown>);
    return {
      ...data,
      payload: {
        ...data.payload,
        buffered_alerts: alerts,
      },
    };
  },
};

export { DRAIN_BUFFER_LUA };
