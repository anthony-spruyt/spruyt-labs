import type { Redis } from "ioredis";
import type { Histogram } from "prom-client";
import type { Config } from "../config.js";
import type { AgentJob } from "../job/schema.js";
import type { DuplicateAction, JobState, RoleDefinition } from "./types.js";

// Atomic drain: LRANGE all items then DEL key in one round-trip.
// Uses Redis server-side Lua execution, not JavaScript eval().
const DRAIN_BUFFER_LUA = `
local items = redis.call('LRANGE', KEYS[1], 0, -1)
redis.call('DEL', KEYS[1])
return items
`;

const SRE_BUFFER_PREFIX = "agent:sre-alerts:";
const SRE_TRIAGED_PREFIX = "agent:sre-triaged:";

function sreAlertBufferKey(jobId: string): string {
  return `${SRE_BUFFER_PREFIX}${jobId}`;
}

export function sreTriagedKey(repo: string, fingerprint: string): string {
  return `${SRE_TRIAGED_PREFIX}${repo}:${fingerprint}`;
}

export function createSreAlertRole(
  config: Config,
  batchSizeHistogram: Histogram
): RoleDefinition {
  return {
    timeoutMs: 2_700_000,
    cooldownMs: config.SRE_COOLDOWN_MS,
    jobOptions: { attempts: 1 },
    buildIdentity(repo: string, _data: Record<string, unknown>): string {
      return `${repo}--sre-alert`;
    },
    onDuplicate(
      _existing: AgentJob,
      _incoming: AgentJob,
      _state: JobState
    ): DuplicateAction {
      return { action: "buffer" };
    },
    bufferKey: sreAlertBufferKey,
    async drainBuffer(
      jobId: string,
      job: AgentJob,
      redis: Redis
    ): Promise<AgentJob> {
      const items = (await redis.eval(
        DRAIN_BUFFER_LUA,
        1,
        sreAlertBufferKey(jobId)
      )) as string[];
      const { alerts: _, ...originalData } = job.data ?? {};
      const buffered = (items ?? []).map(
        (i) => JSON.parse(i) as Record<string, unknown>
      );
      const alerts = [originalData, ...buffered];
      batchSizeHistogram.observe(alerts.length);
      return {
        ...job,
        data: {
          ...job.data,
          alerts,
        },
      };
    },
    getJobDelay(job: AgentJob): number {
      const raw = Number(
        job.data.batch_window_ms ?? config.SRE_BATCH_WINDOW_MS
      );
      return Math.max(0, Math.min(raw, 21_600_000));
    },
  };
}

export { DRAIN_BUFFER_LUA, SRE_TRIAGED_PREFIX };
