# SRE Batch Observability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable batch cap, batch window (delayed jobs), histogram metric, and field rename to the SRE alert batching system.

**Architecture:** Factory pattern for SRE role (closed-over config + metrics). BullMQ delayed jobs for cold-start batching window. Two config env vars, one new histogram, field rename `buffered_alerts` → `alerts`.

**Tech Stack:** TypeScript, BullMQ, ioredis, prom-client, Zod, Vitest

**Issue:** #1184 **Spec:** `docs/superpowers/specs/2026-05-02-sre-batch-observability-design.md`

______________________________________________________________________

## File Map

| File                                                                  | Action | Responsibility                                   |
| --------------------------------------------------------------------- | ------ | ------------------------------------------------ |
| `ts/agent-queue-worker/src/config.ts`                                 | Modify | Add `SRE_BATCH_MAX_SIZE`, `SRE_BATCH_WINDOW_MS`  |
| `ts/agent-queue-worker/src/config.test.ts`                            | Modify | Test new config fields                           |
| `ts/agent-queue-worker/src/metrics.ts`                                | Modify | Add `sreBatchSize` histogram                     |
| `ts/agent-queue-worker/src/roles/types.ts`                            | Modify | Add `"delayed"` to `JobState`, add `getJobDelay` |
| `ts/agent-queue-worker/src/roles/sre-role.ts`                         | Modify | Convert to factory with closed-over deps         |
| `ts/agent-queue-worker/src/roles/registry.ts`                         | Modify | Thread config + histogram                        |
| `ts/agent-queue-worker/src/roles/roles.test.ts`                       | Modify | Update setup, add new tests                      |
| `ts/agent-queue-worker/src/http/routes.ts`                            | Modify | Config LTRIM, delay, Lua comment                 |
| `ts/agent-queue-worker/src/http/server.ts`                            | Modify | Remove redundant `config` from `ServerDeps`      |
| `ts/agent-queue-worker/src/queue/lifecycle.ts`                        | Modify | Config LTRIM, field rename                       |
| `ts/agent-queue-worker/src/index.ts`                                  | Modify | Thread new deps                                  |
| `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml` | Modify | Add env vars                                     |

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ts/agent-queue-worker && npx vitest run src/config.test.ts` Expected: FAIL — `SRE_BATCH_MAX_SIZE` and `SRE_BATCH_WINDOW_MS` not in config type

- [ ] **Step 3: Add config fields**

In `ts/agent-queue-worker/src/config.ts`, add two fields to the `ConfigSchema` object, before the closing `});` on line 21:

```ts
SRE_BATCH_MAX_SIZE: z.coerce.number().int().min(1).default(50),
SRE_BATCH_WINDOW_MS: z.coerce.number().int().min(0).default(60_000),
```

Also add cleanup in `config.test.ts` `beforeEach` — after `delete process.env.GITHUB_TOKEN;` add:

```ts
delete process.env.SRE_BATCH_MAX_SIZE;
delete process.env.SRE_BATCH_WINDOW_MS;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/config.test.ts` Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add ts/agent-queue-worker/src/config.ts ts/agent-queue-worker/src/config.test.ts
git commit -m "feat(agent-worker): add SRE_BATCH_MAX_SIZE and SRE_BATCH_WINDOW_MS config

Ref #1184"
```

______________________________________________________________________

### Task 2: Histogram Metric + Types

**Files:**

- Modify: `ts/agent-queue-worker/src/metrics.ts`

- Modify: `ts/agent-queue-worker/src/roles/types.ts`

- [ ] **Step 1: Add histogram to metrics.ts**

Add at the end of `ts/agent-queue-worker/src/metrics.ts`, after `dedupActionCounter`:

```ts
export const sreBatchSize = new Histogram({
  name: "agent_sre_batch_size",
  help: "Number of alerts drained per SRE batch",
  buckets: [1, 5, 10, 20, 50],
  registers: [registry],
});
```

- [ ] **Step 2: Update JobState and RoleDefinition in types.ts**

In `ts/agent-queue-worker/src/roles/types.ts`:

Change line 11:

```ts
export type JobState = "waiting" | "prioritized" | "active";
```

to:

```ts
export type JobState = "waiting" | "prioritized" | "active" | "delayed";
```

Add after line 28 (`drainBuffer?` method), before the closing `}`:

```ts
getJobDelay?(job: AgentJob): number;
```

- [ ] **Step 3: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS — new types/metrics are additive, no consumers broken yet

- [ ] **Step 4: Commit**

```bash
git add ts/agent-queue-worker/src/metrics.ts ts/agent-queue-worker/src/roles/types.ts
git commit -m "feat(agent-worker): add batch size histogram and delayed job state

Ref #1184"
```

______________________________________________________________________

### Task 3: SRE Role Factory

**Files:**

- Modify: `ts/agent-queue-worker/src/roles/sre-role.ts`

- Modify: `ts/agent-queue-worker/src/roles/registry.ts`

- Modify: `ts/agent-queue-worker/src/index.ts`

- Modify: `ts/agent-queue-worker/src/roles/roles.test.ts`

- [ ] **Step 1: Write failing tests for factory behavior**

In `ts/agent-queue-worker/src/roles/roles.test.ts`, update imports at the top (lines 1-4) to:

```ts
import { describe, expect, it, vi } from "vitest";
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
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);
```

Add a new `describe` block at the end of the file, before the closing:

```ts
describe("sre getJobDelay", () => {
  const def = registry.get("sre");

  it("returns batch window for alert trigger", () => {
    const job = { ...base, role: "sre" as const, payload: { trigger: "alert" } };
    expect(def.getJobDelay!(job)).toBe(60_000);
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ts/agent-queue-worker && npx vitest run src/roles/roles.test.ts` Expected: FAIL — `createDefaultRegistry` doesn't accept arguments yet

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

function sreBufferKey(jobId: string): string {
  return `${SRE_BUFFER_PREFIX}${jobId}`;
}

export function createSreRole(
  config: Config,
  batchSizeHistogram: Histogram
): RoleDefinition {
  return {
    timeoutMs: 900_000,
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
      const items = (await redis.eval(
        DRAIN_BUFFER_LUA,
        1,
        sreBufferKey(jobId)
      )) as string[];
      if (!items || items.length === 0) return data;
      batchSizeHistogram.observe(items.length);
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
        return config.SRE_BATCH_WINDOW_MS;
      }
      return 0;
    },
  };
}

export { DRAIN_BUFFER_LUA };
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
git commit -m "feat(agent-worker): convert SRE role to factory with histogram + delay

Closes over config and batch size histogram for testability.
getJobDelay returns SRE_BATCH_WINDOW_MS for alert triggers, 0 for scheduled.
Field rename: buffered_alerts → alerts.

Ref #1184"
```

______________________________________________________________________

### Task 4: Drain Buffer Tests

**Files:**

- Modify: `ts/agent-queue-worker/src/roles/roles.test.ts`

- [ ] **Step 1: Write drainBuffer tests**

Add to `ts/agent-queue-worker/src/roles/roles.test.ts`. Add `beforeEach` to reset the mock, and a new `describe` block:

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

    expect(mockHistogram.observe).toHaveBeenCalledWith(5);
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

### Task 5: Routes — Config LTRIM + Batch Window + Lua Comment

**Files:**

- Modify: `ts/agent-queue-worker/src/http/routes.ts:26-35, 93-103, 130-142`

- Modify: `ts/agent-queue-worker/src/http/server.ts:16-19`

- [ ] **Step 1: Add config to RouteDeps and update LTRIM**

In `ts/agent-queue-worker/src/http/routes.ts`:

Add import for Config at the top (after existing imports):

```ts
import type { Config } from "../config.js";
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

- [ ] **Step 2: Add Lua script comment**

Replace the `ATOMIC_UPDATE_IF_WAITING_LUA` comment block (lines 22-35) with:

```ts
// Atomic state-checked update: only HSET if job is still in wait/prioritized/paused.
// The non-atomic getJob+getState before this call is acceptable because this Lua
// re-validates state atomically — the outer check is an optimization to avoid
// unnecessary EVAL calls, not a correctness dependency.
// NOTE: Does not check the BullMQ delayed sorted set. This is safe because no
// onDuplicate implementation returns "replace" for delayed jobs (SRE alerts always
// return "buffer"; all other roles discard non-waiting/prioritized states). If a
// future role needs to replace delayed jobs, extend this script to check the delayed set.
const ATOMIC_UPDATE_IF_WAITING_LUA = `
local inWait   = redis.call('LPOS', KEYS[1], ARGV[2])
local inPrio   = redis.call('ZSCORE', KEYS[2], ARGV[2])
local inPaused = redis.call('LPOS', KEYS[3], ARGV[2])
if inWait ~= false or inPrio ~= false or inPaused ~= false then
  redis.call('HSET', KEYS[4], 'data', ARGV[1])
  return 1
end
return 0
`;
```

- [ ] **Step 3: Config-ify LTRIM in buffer path**

In `handleAddJob`, change line 96:

```ts
await deps.redis.ltrim(bufKey, -50, -1);
```

to:

```ts
await deps.redis.ltrim(bufKey, -deps.config.SRE_BATCH_MAX_SIZE, -1);
```

- [ ] **Step 4: Add delay to queue.add**

In `handleAddJob`, change the `queue.add` call (lines 131-136):

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

- [ ] **Step 5: Remove redundant config from ServerDeps**

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

- [ ] **Step 6: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 7: Run all tests**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All PASS

- [ ] **Step 8: Commit**

```bash
git add ts/agent-queue-worker/src/http/routes.ts ts/agent-queue-worker/src/http/server.ts
git commit -m "feat(agent-worker): config-ify LTRIM cap and add batch window delay

LTRIM uses SRE_BATCH_MAX_SIZE from config instead of hardcoded -50.
New jobs use getJobDelay for BullMQ delayed job support.
Lua script comment documents delayed set constraint.

Ref #1184"
```

______________________________________________________________________

### Task 6: Lifecycle — Config LTRIM + Field Rename

**Files:**

- Modify: `ts/agent-queue-worker/src/queue/lifecycle.ts:45, 71`

- [ ] **Step 1: Rename field reference**

In `ts/agent-queue-worker/src/queue/lifecycle.ts`, change line 45:

```ts
const alerts = drainedData.payload?.buffered_alerts as
```

to:

```ts
const alerts = drainedData.payload?.alerts as
```

- [ ] **Step 2: Config-ify LTRIM in fallback re-push**

Change line 71:

```ts
await redis.ltrim(bufKey, -50, -1);
```

to:

```ts
await redis.ltrim(bufKey, -config.SRE_BATCH_MAX_SIZE, -1);
```

- [ ] **Step 3: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 4: Run all tests**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add ts/agent-queue-worker/src/queue/lifecycle.ts
git commit -m "feat(agent-worker): config-ify lifecycle LTRIM and rename buffered_alerts

Uses SRE_BATCH_MAX_SIZE for re-push LTRIM cap.
Field rename: buffered_alerts → alerts for consistency.

Ref #1184"
```

______________________________________________________________________

### Task 7: Helm Values

**Files:**

- Modify: `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml:27-30`

- [ ] **Step 1: Add env vars**

In `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml`, add after the `GITHUB_OWNER` line (line 30), before `envFrom`:

```yaml
          SRE_BATCH_MAX_SIZE: "50"
          SRE_BATCH_WINDOW_MS: "60000"
```

- [ ] **Step 2: Verify YAML is valid**

Run: `yamllint cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml` Expected: No errors (warnings about line length are OK)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml
git commit -m "feat(agent-worker): add SRE batch config env vars to Helm values

SRE_BATCH_MAX_SIZE=50, SRE_BATCH_WINDOW_MS=60000 (1 minute window).

Ref #1184"
```

______________________________________________________________________

### Task 8: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All PASS, no regressions

- [ ] **Step 2: Run typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: PASS

- [ ] **Step 3: Verify no missed hardcoded -50**

Run: `grep -rn "\-50" ts/agent-queue-worker/src/ --include="*.ts"` Expected: No results (all replaced with config)

- [ ] **Step 4: Verify no missed buffered_alerts**

Run: `grep -rn "buffered_alerts" ts/agent-queue-worker/src/ --include="*.ts"` Expected: No results (all renamed to alerts)

- [ ] **Step 5: Verify metrics endpoint includes histogram**

Run: `grep -n "agent_sre_batch_size" ts/agent-queue-worker/src/metrics.ts` Expected: Line with histogram definition
