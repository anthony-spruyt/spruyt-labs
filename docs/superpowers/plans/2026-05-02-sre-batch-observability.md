# SRE Batch Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable batch cap, batch window (delayed jobs), configurable cooldown, histogram metric, fingerprint-based suppression, and field rename to the SRE alert batching system.

**Architecture:** Factory pattern for SRE role (closed-over config + metrics). BullMQ delayed jobs for cold-start batching window. Per-job overrides for `batch_window_ms` and `triage_suppress_s`. Fingerprint suppression via Redis TTL keys. Four config env vars, one new histogram, one new counter, field rename `buffered_alerts` -> `alerts`.

**Tech Stack:** TypeScript, BullMQ, ioredis, prom-client, Zod, Vitest

**Issue:** #1184 **Spec:** `docs/superpowers/specs/2026-05-02-sre-batch-observability-design.md`

**Prior art:** Quick fix `2f5b47c` already deployed -- added `cooldownMs` to `RoleDefinition`, `"delayed"` to `JobState`, completed-state buffer path in routes.ts, cooldown delay in lifecycle.ts. This plan builds on top; do NOT revert or duplicate those changes.

______________________________________________________________________

## File Map

| File                                                                  | Action | Responsibility                                                   |
| --------------------------------------------------------------------- | ------ | ---------------------------------------------------------------- |
| `ts/agent-queue-worker/src/config.ts`                                 | Modify | Add 4 SRE config fields                                          |
| `ts/agent-queue-worker/src/config.test.ts`                            | Modify | Test new config fields                                           |
| `ts/agent-queue-worker/src/metrics.ts`                                | Modify | Add `sreBatchSize` histogram + `sreSuppressed` counter           |
| `ts/agent-queue-worker/src/roles/types.ts`                            | Modify | Add optional `getJobDelay` method                                |
| `ts/agent-queue-worker/src/roles/sre-role.ts`                         | Modify | Convert to factory with closed-over deps                         |
| `ts/agent-queue-worker/src/roles/registry.ts`                         | Modify | Thread config + histogram                                        |
| `ts/agent-queue-worker/src/roles/roles.test.ts`                       | Modify | Update setup, add new tests                                      |
| `ts/agent-queue-worker/src/http/routes.ts`                            | Modify | Fingerprint suppression, config LTRIM, batch window, Lua comment |
| `ts/agent-queue-worker/src/http/server.ts`                            | Modify | Remove redundant `config` from `ServerDeps`                      |
| `ts/agent-queue-worker/src/queue/lifecycle.ts`                        | Modify | Triaged markers, config LTRIM, field rename                      |
| `ts/agent-queue-worker/src/index.ts`                                  | Modify | Thread new deps                                                  |
| `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml` | Modify | Add 4 env vars                                                   |

______________________________________________________________________

### Task 1: Config Schema

**Files:**

- Modify: `ts/agent-queue-worker/src/config.ts:5-21`

- Modify: `ts/agent-queue-worker/src/config.test.ts`

- [ ] **Step 1: Write failing tests for new config fields**

Add to `ts/agent-queue-worker/src/config.test.ts`, inside the existing `describe("loadConfig")` block, after the last `it()`:

```ts
it("defaults SRE_BATCH_MAX_SIZE to 50", () => {
  Object.assign(process.env, VALID_ENV);
  const cfg = loadConfig();
  expect(cfg.SRE_BATCH_MAX_SIZE).toBe(50);
});

it("coerces SRE_BATCH_MAX_SIZE string to number", () => {
  Object.assign(process.env, VALID_ENV, { SRE_BATCH_MAX_SIZE: "25" });
  const cfg = loadConfig();
  expect(cfg.SRE_BATCH_MAX_SIZE).toBe(25);
});

it("throws when SRE_BATCH_MAX_SIZE is 0", () => {
  Object.assign(process.env, VALID_ENV, { SRE_BATCH_MAX_SIZE: "0" });
  expect(() => loadConfig()).toThrow();
});

it("defaults SRE_BATCH_WINDOW_MS to 60000", () => {
  Object.assign(process.env, VALID_ENV);
  const cfg = loadConfig();
  expect(cfg.SRE_BATCH_WINDOW_MS).toBe(60_000);
});

it("allows SRE_BATCH_WINDOW_MS of 0 to disable delay", () => {
  Object.assign(process.env, VALID_ENV, { SRE_BATCH_WINDOW_MS: "0" });
  const cfg = loadConfig();
  expect(cfg.SRE_BATCH_WINDOW_MS).toBe(0);
});

it("defaults SRE_COOLDOWN_MS to 300000", () => {
  Object.assign(process.env, VALID_ENV);
  const cfg = loadConfig();
  expect(cfg.SRE_COOLDOWN_MS).toBe(300_000);
});

it("allows SRE_COOLDOWN_MS of 0 to disable cooldown", () => {
  Object.assign(process.env, VALID_ENV, { SRE_COOLDOWN_MS: "0" });
  const cfg = loadConfig();
  expect(cfg.SRE_COOLDOWN_MS).toBe(0);
});

it("defaults SRE_TRIAGE_SUPPRESS_S to 3600", () => {
  Object.assign(process.env, VALID_ENV);
  const cfg = loadConfig();
  expect(cfg.SRE_TRIAGE_SUPPRESS_S).toBe(3600);
});

it("allows SRE_TRIAGE_SUPPRESS_S of 0 to disable suppression", () => {
  Object.assign(process.env, VALID_ENV, { SRE_TRIAGE_SUPPRESS_S: "0" });
  const cfg = loadConfig();
  expect(cfg.SRE_TRIAGE_SUPPRESS_S).toBe(0);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ts/agent-queue-worker && npx vitest run src/config.test.ts` Expected: FAIL -- new fields not in config type

- [ ] **Step 3: Add config fields**

In `ts/agent-queue-worker/src/config.ts`, add four fields to `ConfigSchema`, before the closing `});`:

```ts
SRE_BATCH_MAX_SIZE: z.coerce.number().int().min(1).default(50),
SRE_BATCH_WINDOW_MS: z.coerce.number().int().min(0).default(60_000),
SRE_COOLDOWN_MS: z.coerce.number().int().min(0).default(300_000),
SRE_TRIAGE_SUPPRESS_S: z.coerce.number().int().min(0).default(3600),
```

Also add cleanup in `config.test.ts` `beforeEach` -- after `delete process.env.GITHUB_TOKEN;` add:

```ts
delete process.env.SRE_BATCH_MAX_SIZE;
delete process.env.SRE_BATCH_WINDOW_MS;
delete process.env.SRE_COOLDOWN_MS;
delete process.env.SRE_TRIAGE_SUPPRESS_S;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/config.test.ts` Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add ts/agent-queue-worker/src/config.ts ts/agent-queue-worker/src/config.test.ts
git commit -m "feat(agent-worker): add SRE batch, cooldown, and suppression config

Ref #1184"
```

______________________________________________________________________

### Task 2: Histogram Metric + Suppression Counter + Types

**Files:**

- Modify: `ts/agent-queue-worker/src/metrics.ts`

- Modify: `ts/agent-queue-worker/src/roles/types.ts`

- [ ] **Step 1: Add histogram and counter to metrics.ts**

Add at the end of `ts/agent-queue-worker/src/metrics.ts`, after `dedupActionCounter`:

```ts
export const sreBatchSize = new Histogram({
  name: "agent_sre_batch_size",
  help: "Total alerts per SRE batch (trigger + buffered)",
  buckets: [1, 5, 10, 20, 50],
  registers: [registry],
});

export const sreSuppressed = new Counter({
  name: "agent_sre_suppressed_total",
  help: "Alerts suppressed by fingerprint dedup",
  labelNames: ["role"] as const,
  registers: [registry],
});
```

- [ ] **Step 2: Add getJobDelay to RoleDefinition in types.ts**

In `ts/agent-queue-worker/src/roles/types.ts`, add after the `drainBuffer?` method (line 29), before the closing `}`:

```ts
getJobDelay?(job: AgentJob): number;
```

Note: `"delayed"` in `JobState` and `cooldownMs` on `RoleDefinition` already exist from quick fix -- do NOT re-add.

- [ ] **Step 3: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS -- new types/metrics are additive, no consumers broken yet

- [ ] **Step 4: Commit**

```bash
git add ts/agent-queue-worker/src/metrics.ts ts/agent-queue-worker/src/roles/types.ts
git commit -m "feat(agent-worker): add batch size histogram, suppression counter, getJobDelay type

Ref #1184"
```

______________________________________________________________________

### Task 3: SRE Role Factory + Registry + Index

**Files:**

- Modify: `ts/agent-queue-worker/src/roles/sre-role.ts`

- Modify: `ts/agent-queue-worker/src/roles/registry.ts`

- Modify: `ts/agent-queue-worker/src/index.ts`

- Modify: `ts/agent-queue-worker/src/roles/roles.test.ts`

- [ ] **Step 1: Write failing tests for factory behavior**

In `ts/agent-queue-worker/src/roles/roles.test.ts`, update imports at the top (lines 1-5) to:

```ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createDefaultRegistry } from "./registry.js";
import { resolveDuplicateAction } from "./types.js";
import type { AgentJob } from "../job/schema.js";
import type { JobState } from "./types.js";
import { Histogram } from "prom-client";
import type { Config } from "../config.js";
```

Replace line 7 (`const registry = createDefaultRegistry();`) with:

```ts
const mockConfig = {
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);
```

Add new `describe` blocks at the end of the file, before the closing:

```ts
describe("sre getJobDelay", () => {
  const def = registry.get("sre");

  it("returns batch window for alert trigger", () => {
    const job = { ...base, role: "sre" as const, payload: { trigger: "alert" } };
    expect(def.getJobDelay!(job)).toBe(60_000);
  });

  it("returns per-job override when present", () => {
    const job = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert", batch_window_ms: 30_000 },
    };
    expect(def.getJobDelay!(job)).toBe(30_000);
  });

  it("caps per-job override at 6 hours", () => {
    const job = {
      ...base,
      role: "sre" as const,
      payload: { trigger: "alert", batch_window_ms: 999_999_999 },
    };
    expect(def.getJobDelay!(job)).toBe(21_600_000);
  });

  it("returns 0 for scheduled jobs", () => {
    const job = { ...base, role: "sre" as const, dedup_key: "d1" };
    expect(def.getJobDelay!(job)).toBe(0);
  });

  it("returns 0 when batch window is 0", () => {
    const zeroConfig = { ...mockConfig, SRE_BATCH_WINDOW_MS: 0 } as Config;
    const zeroHistogram = { observe: vi.fn() } as unknown as Histogram;
    const zeroRegistry = createDefaultRegistry(zeroConfig, zeroHistogram);
    const def2 = zeroRegistry.get("sre");
    const job = { ...base, role: "sre" as const, payload: { trigger: "alert" } };
    expect(def2.getJobDelay!(job)).toBe(0);
  });
});

describe("sre cooldownMs from config", () => {
  it("reads cooldownMs from SRE_COOLDOWN_MS config", () => {
    const def = registry.get("sre");
    expect(def.cooldownMs).toBe(300_000);
  });

  it("respects custom cooldown value", () => {
    const customConfig = { ...mockConfig, SRE_COOLDOWN_MS: 120_000 } as Config;
    const customRegistry = createDefaultRegistry(customConfig, mockHistogram);
    const def = customRegistry.get("sre");
    expect(def.cooldownMs).toBe(120_000);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ts/agent-queue-worker && npx vitest run src/roles/roles.test.ts` Expected: FAIL -- `createDefaultRegistry` doesn't accept arguments yet

- [ ] **Step 3: Convert sre-role.ts to factory**

Replace entire contents of `ts/agent-queue-worker/src/roles/sre-role.ts` with:

```ts
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
      const alerts = items.map(
        (i) => JSON.parse(i) as Record<string, unknown>
      );
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
        const raw = Number(job.payload?.batch_window_ms ?? config.SRE_BATCH_WINDOW_MS);
        return Math.min(raw, 21_600_000);
      }
      return 0;
    },
  };
}

export { DRAIN_BUFFER_LUA, SRE_TRIAGED_PREFIX };
```

- [ ] **Step 4: Update registry.ts**

Replace entire contents of `ts/agent-queue-worker/src/roles/registry.ts` with:

```ts
import type { Histogram } from "prom-client";
import type { RoleDefinition } from "./types.js";
import type { Config } from "../config.js";
import { createPrRole } from "./pr-role.js";
import { validateRole } from "./validate-role.js";
import { executeRole } from "./execute-role.js";
import { createSreRole } from "./sre-role.js";

export class RoleRegistry {
  private roles = new Map<string, RoleDefinition>();

  register(name: string, definition: RoleDefinition): void {
    this.roles.set(name, definition);
  }

  get(name: string): RoleDefinition {
    const def = this.roles.get(name);
    if (!def) throw new Error(`Unknown role: ${name}`);
    return def;
  }

  has(name: string): boolean {
    return this.roles.has(name);
  }

  names(): string[] {
    return [...this.roles.keys()];
  }
}

export function createDefaultRegistry(
  config: Config,
  batchSizeHistogram: Histogram
): RoleRegistry {
  const registry = new RoleRegistry();
  registry.register("triage", createPrRole("triage", 600_000));
  registry.register("fix", createPrRole("fix", 1_800_000));
  registry.register("validate", validateRole);
  registry.register("execute", executeRole);
  registry.register("sre", createSreRole(config, batchSizeHistogram));
  return registry;
}
```

- [ ] **Step 5: Update index.ts**

In `ts/agent-queue-worker/src/index.ts`, add import at the top (after existing imports):

```ts
import * as metrics from "./metrics.js";
```

Change line 29:

```ts
const registry = createDefaultRegistry();
```

to:

```ts
const registry = createDefaultRegistry(config, metrics.sreBatchSize);
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/roles/roles.test.ts` Expected: All PASS

- [ ] **Step 7: Run full typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add ts/agent-queue-worker/src/roles/sre-role.ts ts/agent-queue-worker/src/roles/registry.ts ts/agent-queue-worker/src/index.ts ts/agent-queue-worker/src/roles/roles.test.ts
git commit -m "feat(agent-worker): convert SRE role to factory with config + histogram

Closes over config for cooldown, batch window, and batch size histogram.
getJobDelay supports per-job batch_window_ms override.
Field rename: buffered_alerts -> alerts.

Ref #1184"
```

______________________________________________________________________

### Task 4: Drain Buffer Tests

**Files:**

- Modify: `ts/agent-queue-worker/src/roles/roles.test.ts`

- [ ] **Step 1: Write drainBuffer tests**

Add to `ts/agent-queue-worker/src/roles/roles.test.ts`. Add a new `describe` block:

```ts
describe("sre drainBuffer", () => {
  const def = registry.get("sre");
  const job: AgentJob = {
    ...base,
    role: "sre" as const,
    payload: { trigger: "alert", alertname: "HighCPU" },
  };

  beforeEach(() => {
    vi.mocked(mockHistogram.observe).mockClear();
  });

  it("observes histogram with drained count", async () => {
    const items = [
      JSON.stringify({ alertname: "A1" }),
      JSON.stringify({ alertname: "A2" }),
      JSON.stringify({ alertname: "A3" }),
      JSON.stringify({ alertname: "A4" }),
      JSON.stringify({ alertname: "A5" }),
    ];
    const mockRedis = {
      eval: vi.fn().mockResolvedValue(items),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(6);
    expect(result.payload?.alerts).toHaveLength(5);
  });

  it("uses alerts field not buffered_alerts", async () => {
    const items = [JSON.stringify({ alertname: "A1" })];
    const mockRedis = {
      eval: vi.fn().mockResolvedValue(items),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(result.payload?.alerts).toBeDefined();
    expect(result.payload?.buffered_alerts).toBeUndefined();
  });

  it("does not observe histogram when buffer is empty", async () => {
    const mockRedis = {
      eval: vi.fn().mockResolvedValue([]),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).not.toHaveBeenCalled();
    expect(result).toBe(job);
  });

  it("does not observe histogram when buffer is null", async () => {
    const mockRedis = {
      eval: vi.fn().mockResolvedValue(null),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).not.toHaveBeenCalled();
    expect(result).toBe(job);
  });
});
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/roles/roles.test.ts` Expected: All PASS (implementation was done in Task 3)

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/roles/roles.test.ts
git commit -m "test(agent-worker): add drainBuffer histogram and field rename tests

Ref #1184"
```

______________________________________________________________________

### Task 5: Routes -- Fingerprint Suppression + Config LTRIM + Batch Window

**Files:**

- Modify: `ts/agent-queue-worker/src/http/routes.ts`

- Modify: `ts/agent-queue-worker/src/http/server.ts`

- [ ] **Step 1: Add config to RouteDeps**

In `ts/agent-queue-worker/src/http/routes.ts`:

Add imports at the top (after existing imports):

```ts
import type { Config } from "../config.js";
import { sreTriagedKey } from "../roles/sre-role.js";
```

Add `config: Config;` to the `RouteDeps` interface (after `rateLimiter: RateLimiter;`):

```ts
export interface RouteDeps {
  queue: Queue;
  redis: Redis;
  processor: Processor;
  registry: RoleRegistry;
  circuitBreaker: CircuitBreaker;
  rateLimiter: RateLimiter;
  config: Config;
}
```

- [ ] **Step 2: Add fingerprint suppression check**

In `handleAddJob`, add after the circuit breaker check (after `if (circuit.open)` block, before `const identity = buildJobIdentity`):

```ts
if (data.payload?.trigger === "alert" && data.payload?.fingerprint) {
  const fpKey = sreTriagedKey(data.repo, String(data.payload.fingerprint));
  const triaged = await deps.redis.exists(fpKey);
  if (triaged) {
    metrics.sreSuppressed.inc({ role: data.role });
    return json(res, 200, { added: false, reason: "already_triaged" });
  }
}
```

- [ ] **Step 3: Extend Lua script comment**

Replace the `ATOMIC_UPDATE_IF_WAITING_LUA` comment block (lines 21-25) with:

```ts
// Atomic state-checked update: only HSET if job is still in wait/prioritized/paused.
// The non-atomic getJob+getState before this call is acceptable because this Lua
// re-validates state atomically -- the outer check is an optimization to avoid
// unnecessary EVAL calls, not a correctness dependency.
// NOTE: Does not check the BullMQ delayed sorted set. This is safe because no
// onDuplicate implementation returns "replace" for delayed jobs (SRE alerts always
// return "buffer"; all other roles discard non-waiting/prioritized states). If a
// future role needs to replace delayed jobs, extend this script to check the delayed set.
// Uses Redis EVAL command (server-side Lua execution), not JavaScript eval().
```

- [ ] **Step 4: Config-ify LTRIM in completed-state buffer path**

In `handleAddJob`, change the completed-state buffer LTRIM (around line 76):

```ts
await deps.redis.ltrim(bufKey, -50, -1);
```

to:

```ts
await deps.redis.ltrim(bufKey, -deps.config.SRE_BATCH_MAX_SIZE, -1);
```

- [ ] **Step 5: Config-ify LTRIM in active/waiting buffer path**

In `handleAddJob`, change the active/waiting buffer LTRIM (around line 133):

```ts
await deps.redis.ltrim(bufKey, -50, -1);
```

to:

```ts
await deps.redis.ltrim(bufKey, -deps.config.SRE_BATCH_MAX_SIZE, -1);
```

- [ ] **Step 6: Add batch window delay to new job creation**

In `handleAddJob`, change the final `queue.add` call (around line 168):

```ts
await deps.queue.add(data.role, data, {
  ...DEFAULT_JOB_OPTIONS,
  ...roleDef.jobOptions,
  jobId,
  priority: data.priority,
});
```

to:

```ts
const delay = roleDef.getJobDelay?.(data) ?? 0;
await deps.queue.add(data.role, data, {
  ...DEFAULT_JOB_OPTIONS,
  ...roleDef.jobOptions,
  jobId,
  priority: data.priority,
  ...(delay > 0 && { delay }),
});
```

- [ ] **Step 7: Remove redundant config from ServerDeps**

In `ts/agent-queue-worker/src/http/server.ts`, change lines 16-19:

```ts
export interface ServerDeps extends RouteDeps {
  config: Config;
  isReady: () => boolean;
}
```

to:

```ts
export interface ServerDeps extends RouteDeps {
  isReady: () => boolean;
}
```

Remove the now-unused `Config` import on line 2:

```ts
import type { Config } from "../config.js";
```

- [ ] **Step 8: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 9: Run all tests**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All PASS

- [ ] **Step 10: Commit**

```bash
git add ts/agent-queue-worker/src/http/routes.ts ts/agent-queue-worker/src/http/server.ts
git commit -m "feat(agent-worker): fingerprint suppression, config LTRIM, batch window delay

Fingerprint check before identity resolution discards already-triaged alerts.
LTRIM uses SRE_BATCH_MAX_SIZE from config instead of hardcoded -50.
New jobs use getJobDelay for BullMQ delayed job support.
Lua script comment documents delayed set constraint.

Ref #1184"
```

______________________________________________________________________

### Task 6: Lifecycle -- Triaged Markers + Config LTRIM + Field Rename

**Files:**

- Modify: `ts/agent-queue-worker/src/queue/lifecycle.ts`

- [ ] **Step 1: Add import for sreTriagedKey**

In `ts/agent-queue-worker/src/queue/lifecycle.ts`, add import at the top (after existing imports):

```ts
import { sreTriagedKey } from "../roles/sre-role.js";
```

- [ ] **Step 2: Add triaged marker logic**

In the `worker.on("completed")` handler, add fingerprint suppression marker writing BEFORE the existing drain logic. After `if (!roleDef.bufferKey || !roleDef.drainBuffer) return;` (line 40) and before the `try` block (line 42), add:

```ts
if (job.data.payload?.trigger === "alert") {
  const suppressTtl = Number(
    job.data.payload?.triage_suppress_s ?? config.SRE_TRIAGE_SUPPRESS_S
  );
  const fingerprints = new Set<string>();

  if (job.data.payload?.fingerprint) {
    fingerprints.add(String(job.data.payload.fingerprint));
  }
  const processedAlerts = job.data.payload?.alerts as
    | Array<Record<string, unknown>>
    | undefined;
  if (processedAlerts) {
    for (const a of processedAlerts) {
      if (a.fingerprint) fingerprints.add(String(a.fingerprint));
    }
  }

  if (fingerprints.size > 0 && suppressTtl > 0) {
    try {
      const pipeline = redis.pipeline();
      for (const fp of fingerprints) {
        pipeline.set(
          sreTriagedKey(job.data.repo, fp),
          "1",
          "EX",
          suppressTtl
        );
      }
      await pipeline.exec();
      logger.debug("Wrote triaged markers", {
        jobId: job.id,
        count: fingerprints.size,
        ttlSeconds: suppressTtl,
      });
    } catch (err) {
      logger.warn("Failed to write triaged markers", {
        jobId: job.id,
        error: String(err),
      });
    }
  }
}
```

- [ ] **Step 3: Rename field reference**

In the same file, change line 44:

```ts
const alerts = drainedData.payload?.buffered_alerts as
```

to:

```ts
const alerts = drainedData.payload?.alerts as
```

- [ ] **Step 4: Config-ify LTRIM in fallback re-push**

Change line 73:

```ts
await redis.ltrim(bufKey, -50, -1);
```

to:

```ts
await redis.ltrim(bufKey, -config.SRE_BATCH_MAX_SIZE, -1);
```

- [ ] **Step 5: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 6: Run all tests**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add ts/agent-queue-worker/src/queue/lifecycle.ts
git commit -m "feat(agent-worker): write triaged markers on completion, config LTRIM, field rename

Extracts fingerprints from job data + drained alerts, writes Redis TTL keys.
Per-job triage_suppress_s override supported.
LTRIM uses SRE_BATCH_MAX_SIZE config. Field rename: buffered_alerts -> alerts.

Ref #1184"
```

______________________________________________________________________

### Task 7: Helm Values

**Files:**

- Modify: `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml`

- [ ] **Step 1: Add env vars**

In `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml`, add after the `GITHUB_OWNER` line (line 30), before `envFrom`:

```yaml
          SRE_BATCH_MAX_SIZE: "50"
          SRE_BATCH_WINDOW_MS: "60000"
          SRE_COOLDOWN_MS: "300000"
          SRE_TRIAGE_SUPPRESS_S: "3600"
```

- [ ] **Step 2: Verify YAML is valid**

Run: `yamllint cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml` Expected: No errors (warnings about line length are OK)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml
git commit -m "feat(agent-worker): add SRE batch/cooldown/suppression config env vars

SRE_BATCH_MAX_SIZE=50, SRE_BATCH_WINDOW_MS=60000, SRE_COOLDOWN_MS=300000,
SRE_TRIAGE_SUPPRESS_S=3600.

Ref #1184"
```

______________________________________________________________________

### Task 8: n8n Workflow Update

**Note:** This task modifies the n8n SRE alert dispatch workflow. Use n8n MCP tools or update manually in the n8n UI.

- [ ] **Step 1: Identify the workflow**

Find the SRE alert dispatch workflow that contains the Code node shown in the issue. The current code extracts only `alerts[0]` and sends a single dispatch.

- [ ] **Step 2: Update Code node**

Replace the Code node contents with:

```js
const payload = $input.first().json;
const alerts = payload.alerts || [];

return alerts.map(alert => ({
  json: {
    role: 'sre',
    repo: 'anthony-spruyt/spruyt-labs',
    event_type: 'alertmanager_webhook',
    priority: alert.labels?.severity === 'critical' ? 1 : 10,
    payload: {
      trigger: 'alert',
      alertname: alert.labels?.alertname || 'unknown',
      fingerprint: alert.fingerprint || Date.now().toString(),
      alert_payload: JSON.stringify(alert, null, 2),
      batch_window_ms: alert.labels?.severity === 'critical' ? 0 : undefined,
      metaData: {
        workflowId: $workflow.id,
        executionId: $execution.id
      }
    }
  }
}));
```

Key changes:

- `.map()` over `payload.alerts` -- one output per alert (worker batches via identity)

- `fingerprint` at top-level of payload (moved from `metaData`)

- Per-alert `priority` based on severity

- `batch_window_ms: 0` for critical alerts (immediate processing)

- `alert_payload` is single alert JSON, not full webhook

- [ ] **Step 3: Verify downstream node handles multiple items**

Ensure the HTTP Request node after the Code node processes all items (default n8n behavior). Each item becomes a separate POST to the worker.

- [ ] **Step 4: Test with a sample alert**

Trigger a test alert through AlertManager and verify:

- Multiple alerts in one webhook produce multiple worker POSTs
- Each POST has a unique fingerprint
- Worker buffers them under the same job identity

______________________________________________________________________

### Task 9: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All PASS, no regressions

- [ ] **Step 2: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 3: Verify no missed hardcoded -50**

Run: `grep -rn "\-50" ts/agent-queue-worker/src/ --include="*.ts"` Expected: No results in routes.ts or lifecycle.ts (all replaced with config)

- [ ] **Step 4: Verify no missed buffered_alerts**

Run: `grep -rn "buffered_alerts" ts/agent-queue-worker/src/ --include="*.ts"` Expected: No results (all renamed to alerts)

- [ ] **Step 5: Verify metrics endpoint includes new metrics**

Run: `grep -n "agent_sre_batch_size\|agent_sre_suppressed" ts/agent-queue-worker/src/metrics.ts` Expected: Both metrics defined

- [ ] **Step 6: Verify fingerprint suppression key pattern**

Run: `grep -rn "sre-triaged" ts/agent-queue-worker/src/ --include="*.ts"` Expected: Found in routes.ts (check) and lifecycle.ts (write)
