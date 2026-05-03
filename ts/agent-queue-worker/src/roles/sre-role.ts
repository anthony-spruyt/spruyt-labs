import type { Redis } from "ioredis";
import type { Histogram } from "prom-client";
import type { RoleDefinition, DuplicateAction, JobState } from "./types.js";
import type { AgentJob } from "../job/schema.js";
import type { Config } from "../config.js";

// Atomic drain: LRANGE all items then DEL key in one round-trip.
// Uses Redis EVAL command (server-side Lua execution), not JavaScript eval().
const DRAIN_BUFFER_LUA = `
local items = redis.call('LRANGE', KEYS[1], 0, -1)
redis.call('DEL', KEYS[1])
return items
`;

const SRE_BUFFER_PREFIX = "agent:sre-alerts:";
const SRE_TRIAGED_PREFIX = "agent:sre-triaged:";

function sreBufferKey(jobId: string): string {
  return `${SRE_BUFFER_PREFIX}${jobId}`;
}

export function sreTriagedKey(repo: string, fingerprint: string): string {
  return `${SRE_TRIAGED_PREFIX}${repo}:${fingerprint}`;
}

export function createSreRole(
  config: Config,
  batchSizeHistogram: Histogram
): RoleDefinition {
  return {
    timeoutMs: 900_000,
    cooldownMs: config.SRE_COOLDOWN_MS,
    jobOptions: { attempts: 1 },
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
    bufferKey: sreBufferKey,
    async drainBuffer(
      jobId: string,
      data: AgentJob,
      redis: Redis
    ): Promise<AgentJob> {
      // Redis EVAL runs Lua server-side for atomic drain
      const items = (await redis.eval(
        DRAIN_BUFFER_LUA,
        1,
        sreBufferKey(jobId)
      )) as string[];
      if (!items || items.length === 0) return data;
      batchSizeHistogram.observe(items.length + 1);
      const alerts = items.map((i) => JSON.parse(i) as Record<string, unknown>);
      return {
        ...data,
        payload: {
          ...data.payload,
          alerts,
        },
      };
    },
    getJobDelay(job: AgentJob): number {
      if (job.payload?.trigger === "alert") {
        const raw = Number(
          job.payload?.batch_window_ms ?? config.SRE_BATCH_WINDOW_MS
        );
        return Math.min(raw, 21_600_000);
      }
      return 0;
    },
  };
}

export { DRAIN_BUFFER_LUA, SRE_TRIAGED_PREFIX };
