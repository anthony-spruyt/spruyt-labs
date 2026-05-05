# Agent Queue Worker — Job Schema v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure job input schema to envelope + typed data pattern, rename roles, split SRE into two roles, and return detailed validation errors.

**Architecture:** Discriminated union on `role` at the top level selects a typed `data` schema per role. Role definitions receive `data` (typed) instead of the full job. Identity is derived from `role + repo + data`. The SRE role splits into `sre-alert` and `sre-health-check` as independent role registrations.

**Tech Stack:** TypeScript, Zod, BullMQ, Vitest

______________________________________________________________________

## File Structure

| File                                 | Action                                 | Responsibility                                                                       |
| ------------------------------------ | -------------------------------------- | ------------------------------------------------------------------------------------ |
| `src/job/schema.ts`                  | Rewrite                                | Envelope + per-role data schemas, `AgentJobInputSchema`, `AgentJobSchema`            |
| `src/job/identity.ts`                | Modify                                 | Simplify `buildJobIdentity` to use new data shapes, update `extractRole`             |
| `src/job/schema.test.ts`             | Rewrite                                | Tests for new schema shapes                                                          |
| `src/job/identity.test.ts`           | Rewrite                                | Tests for new identity derivation                                                    |
| `src/roles/types.ts`                 | Modify                                 | Change `buildIdentitySegments` signature to `buildIdentity(repo, data)`              |
| `src/roles/renovate-role.ts`         | Create (rename from `pr-role.ts`)      | `renovate-triage` and `renovate-fix` role definitions                                |
| `src/roles/execute-issue-role.ts`    | Create (rename from `execute-role.ts`) | `execute-issue` role definition                                                      |
| `src/roles/sre-alert-role.ts`        | Create (split from `sre-role.ts`)      | `sre-alert` role: buffer, drain, delay, triaged key                                  |
| `src/roles/sre-health-check-role.ts` | Create (split from `sre-role.ts`)      | `sre-health-check` role: replace/discard                                             |
| `src/roles/revert-role.ts`           | Create                                 | `revert` role (stub, TBD schema)                                                     |
| `src/roles/validate-role.ts`         | Modify                                 | Rename role identity segment                                                         |
| `src/roles/registry.ts`              | Modify                                 | Register new role names                                                              |
| `src/roles/pr-role.ts`               | Delete                                 | Replaced by `renovate-role.ts`                                                       |
| `src/roles/execute-role.ts`          | Delete                                 | Replaced by `execute-issue-role.ts`                                                  |
| `src/roles/sre-role.ts`              | Delete                                 | Replaced by `sre-alert-role.ts` + `sre-health-check-role.ts`                         |
| `src/roles/roles.test.ts`            | Rewrite                                | Tests for all renamed/split roles                                                    |
| `src/http/middleware.ts`             | Modify                                 | Return `errors` array with field + message                                           |
| `src/http/routes.ts`                 | Modify                                 | Update field access paths, remove catch block for identity, update suppression check |
| `src/http/routes.test.ts`            | Modify                                 | Update test payloads and assertions                                                  |
| `src/processor.ts`                   | Modify                                 | Update field destructuring for log context                                           |
| `src/queue/lifecycle.ts`             | Modify                                 | Update `data.payload` access to `data.data` for alert checks                         |
| `src/queue/lifecycle.test.ts`        | Modify                                 | Update test job data shapes                                                          |

______________________________________________________________________

### Task 1: Schema — New Zod schemas

**Files:**

- Rewrite: `ts/agent-queue-worker/src/job/schema.ts`

- Test: `ts/agent-queue-worker/src/job/schema.test.ts`

- [ ] **Step 1: Write failing tests for new schema**

Replace `ts/agent-queue-worker/src/job/schema.test.ts` with:

```ts
import { describe, expect, it } from "vitest";
import {
  AgentJobInputSchema,
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
  VALID_ROLES,
} from "./schema.js";

describe("AgentJobInputSchema", () => {
  const triageBase = {
    role: "renovate-triage",
    repo: "org/repo",
    event_type: "pull_request",
    priority: 5,
    data: { pr_number: 42, head_sha: "abc123" },
  };

  it("accepts valid renovate-triage job", () => {
    const result = AgentJobInputSchema.safeParse(triageBase);
    expect(result.success).toBe(true);
  });

  it("rejects renovate-triage without data.pr_number", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      data: { head_sha: "abc123" },
    });
    expect(result.success).toBe(false);
  });

  it("rejects renovate-triage without data.head_sha", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      data: { pr_number: 42 },
    });
    expect(result.success).toBe(false);
  });

  it("rejects renovate-triage with extra keys in data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      data: { pr_number: 42, head_sha: "abc123", extra: "nope" },
    });
    expect(result.success).toBe(false);
  });

  it("accepts valid renovate-fix job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "renovate-fix",
    });
    expect(result.success).toBe(true);
  });

  it("rejects renovate-fix without data.pr_number", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "renovate-fix",
      data: { head_sha: "abc123" },
    });
    expect(result.success).toBe(false);
  });

  it("accepts valid execute-issue job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "execute-issue",
      data: { issue_number: 99 },
    });
    expect(result.success).toBe(true);
  });

  it("rejects execute-issue without data.issue_number", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "execute-issue",
      data: {},
    });
    expect(result.success).toBe(false);
  });

  it("rejects execute-issue with extra keys in data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "execute-issue",
      data: { issue_number: 99, extra: "nope" },
    });
    expect(result.success).toBe(false);
  });

  it("accepts valid sre-alert job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-alert",
      data: { fingerprint: "fp-abc", alertname: "HighCPU", severity: "warning" },
    });
    expect(result.success).toBe(true);
  });

  it("rejects sre-alert without data.fingerprint", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-alert",
      data: { alertname: "HighCPU" },
    });
    expect(result.success).toBe(false);
  });

  it("allows extra keys in sre-alert data (AlertManager passthrough)", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-alert",
      data: { fingerprint: "fp-abc", alertname: "HighCPU", labels: { pod: "x" } },
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid sre-health-check job", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-health-check",
      data: { dedup_key: "2026-05-01" },
    });
    expect(result.success).toBe(true);
  });

  it("rejects sre-health-check without data.dedup_key", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-health-check",
      data: {},
    });
    expect(result.success).toBe(false);
  });

  it("rejects sre-health-check with extra keys", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "sre-health-check",
      data: { dedup_key: "2026-05-01", extra: "nope" },
    });
    expect(result.success).toBe(false);
  });

  it("accepts valid revert job with any data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "revert",
      data: { reason: "ci_failed" },
    });
    expect(result.success).toBe(true);
  });

  it("accepts revert with empty data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "revert",
      data: {},
    });
    expect(result.success).toBe(true);
  });

  it("accepts valid validate job with any data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "validate",
      data: { commit_sha: "abc" },
    });
    expect(result.success).toBe(true);
  });

  it("accepts validate with empty data", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      role: "validate",
      data: {},
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid role", () => {
    const result = AgentJobInputSchema.safeParse({ ...triageBase, role: "nope" });
    expect(result.success).toBe(false);
  });

  it("rejects empty repo", () => {
    const result = AgentJobInputSchema.safeParse({ ...triageBase, repo: "" });
    expect(result.success).toBe(false);
  });

  it("rejects repo containing --", () => {
    const result = AgentJobInputSchema.safeParse({ ...triageBase, repo: "org--repo" });
    expect(result.success).toBe(false);
  });

  it("rejects non-integer priority", () => {
    const result = AgentJobInputSchema.safeParse({ ...triageBase, priority: 1.5 });
    expect(result.success).toBe(false);
  });

  it("rejects missing priority", () => {
    const { priority: _, ...noPriority } = triageBase;
    const result = AgentJobInputSchema.safeParse(noPriority);
    expect(result.success).toBe(false);
  });

  it("rejects missing data", () => {
    const { data: _, ...noData } = triageBase;
    const result = AgentJobInputSchema.safeParse(noData);
    expect(result.success).toBe(false);
  });

  it("strips dispatch_state from input", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      dispatch_state: "dispatched",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dispatch_state" in result.data).toBe(false);
    }
  });

  it("strips dispatched_at from input", () => {
    const result = AgentJobInputSchema.safeParse({
      ...triageBase,
      dispatched_at: "2026-01-01T00:00:00Z",
    });
    expect(result.success).toBe(true);
    if (result.success) {
      expect("dispatched_at" in result.data).toBe(false);
    }
  });

  it("has correct VALID_ROLES list", () => {
    expect([...VALID_ROLES].sort()).toEqual([
      "execute-issue",
      "renovate-fix",
      "renovate-triage",
      "revert",
      "sre-alert",
      "sre-health-check",
      "validate",
    ]);
  });
});

describe("AgentJobSchema (internal)", () => {
  const base = {
    role: "renovate-triage",
    repo: "org/repo",
    event_type: "pull_request",
    priority: 5,
    data: { pr_number: 42, head_sha: "abc123" },
  };

  it("accepts dispatch fields", () => {
    for (const state of ["pending", "dispatched", "failed"]) {
      const result = AgentJobSchema.safeParse({
        ...base,
        dispatch_state: state,
        dispatched_at: "2026-01-01T00:00:00Z",
      });
      expect(result.success).toBe(true);
    }
  });

  it("accepts any data shape (internal schema is permissive)", () => {
    const result = AgentJobSchema.safeParse({
      ...base,
      data: { pr_number: 42, head_sha: "abc", extra: "ok-internally" },
    });
    expect(result.success).toBe(true);
  });
});

describe("DoneRequestSchema", () => {
  it("accepts valid request", () => {
    const result = DoneRequestSchema.safeParse({
      result: { status: "ok" },
      session_token: "00000000-0000-0000-0000-000000000000",
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid uuid", () => {
    const result = DoneRequestSchema.safeParse({
      result: {},
      session_token: "not-a-uuid",
    });
    expect(result.success).toBe(false);
  });

  it("rejects missing session_token", () => {
    const result = DoneRequestSchema.safeParse({ result: { status: "ok" } });
    expect(result.success).toBe(false);
  });
});

describe("FailRequestSchema", () => {
  it("accepts valid reason", () => {
    const result = FailRequestSchema.safeParse({ reason: "timeout" });
    expect(result.success).toBe(true);
  });

  it("rejects empty reason", () => {
    const result = FailRequestSchema.safeParse({ reason: "" });
    expect(result.success).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ts/agent-queue-worker && npx vitest run src/job/schema.test.ts` Expected: All new tests fail (schemas don't exist yet in new shape)

- [ ] **Step 3: Implement new schema**

Replace `ts/agent-queue-worker/src/job/schema.ts` with:

```ts
import { z } from "zod";

export const VALID_ROLES = [
  "renovate-triage",
  "renovate-fix",
  "revert",
  "execute-issue",
  "sre-alert",
  "sre-health-check",
  "validate",
] as const;
export type Role = (typeof VALID_ROLES)[number];

const envelope = {
  repo: z
    .string()
    .min(1)
    .refine((r) => !r.includes("--"), "repo must not contain --"),
  priority: z.number().int().min(1),
  event_type: z.string().min(1),
};

const renovateData = z.strictObject({
  pr_number: z.number().int().positive(),
  head_sha: z.string().min(1),
});

const executeIssueData = z.strictObject({
  issue_number: z.number().int().positive(),
});

const sreAlertData = z
  .object({ fingerprint: z.string().min(1) })
  .passthrough();

const sreHealthCheckData = z.strictObject({
  dedup_key: z.string().min(1),
});

const openData = z.record(z.string(), z.unknown());

export const AgentJobInputSchema = z.discriminatedUnion("role", [
  z.object({ role: z.literal("renovate-triage"), ...envelope, data: renovateData }),
  z.object({ role: z.literal("renovate-fix"), ...envelope, data: renovateData }),
  z.object({ role: z.literal("revert"), ...envelope, data: openData }),
  z.object({ role: z.literal("execute-issue"), ...envelope, data: executeIssueData }),
  z.object({ role: z.literal("sre-alert"), ...envelope, data: sreAlertData }),
  z.object({ role: z.literal("sre-health-check"), ...envelope, data: sreHealthCheckData }),
  z.object({ role: z.literal("validate"), ...envelope, data: openData }),
]);

export type AgentJobInput = z.infer<typeof AgentJobInputSchema>;

export const AgentJobSchema = z.object({
  role: z.enum(VALID_ROLES),
  ...envelope,
  data: z.record(z.string(), z.unknown()),
  dispatched_at: z.string().optional(),
  dispatch_state: z.enum(["pending", "dispatched", "failed"]).optional(),
});

export type AgentJob = z.infer<typeof AgentJobSchema>;

export const DoneRequestSchema = z.object({
  result: z.record(z.string(), z.unknown()),
  session_token: z.string().uuid(),
});

export type DoneRequest = z.infer<typeof DoneRequestSchema>;

export const FailRequestSchema = z.object({
  reason: z.string().min(1),
});

export type FailRequest = z.infer<typeof FailRequestSchema>;

export interface JobResult {
  status: string;
  [key: string]: unknown;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/job/schema.test.ts` Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add ts/agent-queue-worker/src/job/schema.ts ts/agent-queue-worker/src/job/schema.test.ts
git commit -m "feat(agent-queue-worker): rewrite job schema to envelope + typed data pattern

Ref #<issue>"
```

______________________________________________________________________

### Task 2: Role types — Update RoleDefinition interface

**Files:**

- Modify: `ts/agent-queue-worker/src/roles/types.ts`

- [ ] **Step 1: Update RoleDefinition interface**

Replace `ts/agent-queue-worker/src/roles/types.ts` with:

```ts
import type { JobsOptions } from "bullmq";
import type { Redis } from "ioredis";
import type { Config } from "../config.js";
import type { AgentJob } from "../job/schema.js";

export type DuplicateAction =
  | { action: "replace" }
  | { action: "buffer" }
  | { action: "discard" };

export type JobState = "waiting" | "prioritized" | "active" | "delayed";

export type StalenessResult =
  | { stale: false }
  | { stale: true; reason: string };

export interface RoleDefinition {
  readonly timeoutMs: number;
  readonly cooldownMs?: number;
  readonly jobOptions?: Partial<Pick<JobsOptions, "attempts" | "backoff">>;
  buildIdentity(repo: string, data: Record<string, unknown>): string;
  checkStaleness?(job: AgentJob, config: Config): Promise<StalenessResult>;
  onDuplicate?(
    existingData: AgentJob,
    incomingRequest: AgentJob,
    state: JobState
  ): DuplicateAction;
  bufferKey?(jobId: string): string;
  drainBuffer?(jobId: string, data: AgentJob, redis: Redis): Promise<AgentJob>;
  getJobDelay?(job: AgentJob): number;
}

export function resolveDuplicateAction(
  roleDef: RoleDefinition,
  existing: AgentJob,
  incoming: AgentJob,
  state: JobState
): DuplicateAction {
  if (roleDef.onDuplicate) {
    return roleDef.onDuplicate(existing, incoming, state);
  }
  return state === "waiting" || state === "prioritized"
    ? { action: "replace" }
    : { action: "discard" };
}
```

- [ ] **Step 2: Verify typecheck fails (expected — dependents not yet updated)**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit 2>&1 | head -20` Expected: Type errors in role files that still use `buildIdentitySegments`

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/roles/types.ts
git commit -m "refactor(agent-queue-worker): update RoleDefinition interface to buildIdentity(repo, data)

Ref #<issue>"
```

______________________________________________________________________

### Task 3: Role definitions — Rename and split roles

**Files:**

- Create: `ts/agent-queue-worker/src/roles/renovate-role.ts`

- Create: `ts/agent-queue-worker/src/roles/execute-issue-role.ts`

- Create: `ts/agent-queue-worker/src/roles/sre-alert-role.ts`

- Create: `ts/agent-queue-worker/src/roles/sre-health-check-role.ts`

- Create: `ts/agent-queue-worker/src/roles/revert-role.ts`

- Modify: `ts/agent-queue-worker/src/roles/validate-role.ts`

- Delete: `ts/agent-queue-worker/src/roles/pr-role.ts`

- Delete: `ts/agent-queue-worker/src/roles/execute-role.ts`

- Delete: `ts/agent-queue-worker/src/roles/sre-role.ts`

- [ ] **Step 1: Create renovate-role.ts**

Create `ts/agent-queue-worker/src/roles/renovate-role.ts`:

```ts
import type { Config } from "../config.js";
import { getCurrentPrHead } from "../github.js";
import type { AgentJob } from "../job/schema.js";
import type { RoleDefinition, StalenessResult } from "./types.js";

export function createRenovateRole(
  roleName: string,
  timeoutMs: number
): RoleDefinition {
  return {
    timeoutMs,
    buildIdentity(repo: string, data: Record<string, unknown>): string {
      const prNumber = data.pr_number;
      if (!prNumber)
        throw new Error(`data.pr_number required for ${roleName} jobs`);
      return `${repo}--${roleName}--${prNumber}`;
    },
    async checkStaleness(
      job: AgentJob,
      config: Config
    ): Promise<StalenessResult> {
      const prNumber = job.data.pr_number as number | undefined;
      const headSha = job.data.head_sha as string | undefined;
      if (!prNumber || !headSha) return { stale: false };
      try {
        const currentHead = await getCurrentPrHead(
          job.repo,
          prNumber,
          config.GITHUB_TOKEN
        );
        if (currentHead !== headSha) {
          return { stale: true, reason: "head_sha_changed" };
        }
      } catch {
        // GitHub API failure — proceed optimistically
      }
      return { stale: false };
    },
  };
}
```

- [ ] **Step 2: Create execute-issue-role.ts**

Create `ts/agent-queue-worker/src/roles/execute-issue-role.ts`:

```ts
import type { AgentJob } from "../job/schema.js";
import type { DuplicateAction, JobState, RoleDefinition } from "./types.js";

export const executeIssueRole: RoleDefinition = {
  timeoutMs: 3_600_000,
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
```

- [ ] **Step 3: Create sre-alert-role.ts**

Create `ts/agent-queue-worker/src/roles/sre-alert-role.ts`:

```ts
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
    timeoutMs: 900_000,
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
      data: AgentJob,
      redis: Redis
    ): Promise<AgentJob> {
      const items = (await redis.eval(
        DRAIN_BUFFER_LUA,
        1,
        sreAlertBufferKey(jobId)
      )) as string[];
      const { alerts: _, ...originalData } = data.data ?? {};
      const buffered = (items ?? []).map(
        (i) => JSON.parse(i) as Record<string, unknown>
      );
      const alerts = [originalData, ...buffered];
      batchSizeHistogram.observe(alerts.length);
      return {
        ...data,
        data: {
          ...data.data,
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
```

- [ ] **Step 4: Create sre-health-check-role.ts**

Create `ts/agent-queue-worker/src/roles/sre-health-check-role.ts`:

```ts
import type { AgentJob } from "../job/schema.js";
import type { DuplicateAction, JobState, RoleDefinition } from "./types.js";

export const sreHealthCheckRole: RoleDefinition = {
  timeoutMs: 900_000,
  buildIdentity(repo: string, data: Record<string, unknown>): string {
    const dedupKey = data.dedup_key;
    if (!dedupKey)
      throw new Error("data.dedup_key required for sre-health-check jobs");
    return `${repo}--sre-health-check--${dedupKey}`;
  },
  onDuplicate(
    _existing: AgentJob,
    _incoming: AgentJob,
    state: JobState
  ): DuplicateAction {
    return state === "waiting" || state === "prioritized"
      ? { action: "replace" }
      : { action: "discard" };
  },
};
```

- [ ] **Step 5: Create revert-role.ts**

Create `ts/agent-queue-worker/src/roles/revert-role.ts`:

```ts
import type { RoleDefinition } from "./types.js";

export const revertRole: RoleDefinition = {
  timeoutMs: 900_000,
  buildIdentity(repo: string, _data: Record<string, unknown>): string {
    return `${repo}--revert`;
  },
};
```

- [ ] **Step 6: Update validate-role.ts**

Replace `ts/agent-queue-worker/src/roles/validate-role.ts` with:

```ts
import type { RoleDefinition } from "./types.js";

export const validateRole: RoleDefinition = {
  timeoutMs: 1_800_000,
  buildIdentity(repo: string, _data: Record<string, unknown>): string {
    return `${repo}--validate`;
  },
};
```

- [ ] **Step 7: Delete old role files**

```bash
rm ts/agent-queue-worker/src/roles/pr-role.ts
rm ts/agent-queue-worker/src/roles/execute-role.ts
rm ts/agent-queue-worker/src/roles/sre-role.ts
```

- [ ] **Step 8: Commit**

```bash
git add ts/agent-queue-worker/src/roles/renovate-role.ts ts/agent-queue-worker/src/roles/execute-issue-role.ts ts/agent-queue-worker/src/roles/sre-alert-role.ts ts/agent-queue-worker/src/roles/sre-health-check-role.ts ts/agent-queue-worker/src/roles/revert-role.ts ts/agent-queue-worker/src/roles/validate-role.ts
git rm ts/agent-queue-worker/src/roles/pr-role.ts ts/agent-queue-worker/src/roles/execute-role.ts ts/agent-queue-worker/src/roles/sre-role.ts
git commit -m "refactor(agent-queue-worker): rename and split role definitions

Ref #<issue>"
```

______________________________________________________________________

### Task 4: Registry — Wire new role names

**Files:**

- Modify: `ts/agent-queue-worker/src/roles/registry.ts`

- [ ] **Step 1: Update registry**

Replace `ts/agent-queue-worker/src/roles/registry.ts` with:

```ts
import type { Histogram } from "prom-client";
import type { Config } from "../config.js";
import { executeIssueRole } from "./execute-issue-role.js";
import { createRenovateRole } from "./renovate-role.js";
import { revertRole } from "./revert-role.js";
import { createSreAlertRole } from "./sre-alert-role.js";
import { sreHealthCheckRole } from "./sre-health-check-role.js";
import type { RoleDefinition } from "./types.js";
import { validateRole } from "./validate-role.js";

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
  registry.register(
    "renovate-triage",
    createRenovateRole("renovate-triage", 600_000)
  );
  registry.register(
    "renovate-fix",
    createRenovateRole("renovate-fix", 1_800_000)
  );
  registry.register("revert", revertRole);
  registry.register("validate", validateRole);
  registry.register("execute-issue", executeIssueRole);
  registry.register(
    "sre-alert",
    createSreAlertRole(config, batchSizeHistogram)
  );
  registry.register("sre-health-check", sreHealthCheckRole);
  return registry;
}
```

- [ ] **Step 2: Commit**

```bash
git add ts/agent-queue-worker/src/roles/registry.ts
git commit -m "refactor(agent-queue-worker): wire new role names in registry

Ref #<issue>"
```

______________________________________________________________________

### Task 5: Identity — Update buildJobIdentity and extractRole

**Files:**

- Modify: `ts/agent-queue-worker/src/job/identity.ts`

- Rewrite: `ts/agent-queue-worker/src/job/identity.test.ts`

- [ ] **Step 1: Write failing tests**

Replace `ts/agent-queue-worker/src/job/identity.test.ts` with:

```ts
import type { Histogram } from "prom-client";
import { describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import { createDefaultRegistry } from "../roles/registry.js";
import { buildJobIdentity, extractRole } from "./identity.js";
import type { AgentJob } from "./schema.js";

const mockConfig = {
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);

const base: AgentJob = {
  role: "renovate-triage",
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  data: {},
};

describe("buildJobIdentity", () => {
  it("builds renovate-triage identity", () => {
    const id = buildJobIdentity(
      { ...base, data: { pr_number: 42, head_sha: "abc" } },
      registry
    );
    expect(id.jobId).toBe("org/repo--renovate-triage--42");
    expect(id.role).toBe("renovate-triage");
    expect(id.repo).toBe("org/repo");
  });

  it("builds renovate-fix identity", () => {
    const id = buildJobIdentity(
      {
        ...base,
        role: "renovate-fix",
        data: { pr_number: 10, head_sha: "def" },
      },
      registry
    );
    expect(id.jobId).toBe("org/repo--renovate-fix--10");
  });

  it("builds revert identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "revert", data: {} },
      registry
    );
    expect(id.jobId).toBe("org/repo--revert");
  });

  it("builds validate identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "validate", data: {} },
      registry
    );
    expect(id.jobId).toBe("org/repo--validate");
  });

  it("builds execute-issue identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "execute-issue", data: { issue_number: 99 } },
      registry
    );
    expect(id.jobId).toBe("org/repo--execute-issue--99");
  });

  it("throws for execute-issue without data.issue_number", () => {
    expect(() =>
      buildJobIdentity(
        { ...base, role: "execute-issue", data: {} },
        registry
      )
    ).toThrow("data.issue_number required");
  });

  it("builds sre-alert identity", () => {
    const id = buildJobIdentity(
      { ...base, role: "sre-alert", data: { fingerprint: "fp-1" } },
      registry
    );
    expect(id.jobId).toBe("org/repo--sre-alert");
  });

  it("builds sre-health-check identity", () => {
    const id = buildJobIdentity(
      {
        ...base,
        role: "sre-health-check",
        data: { dedup_key: "2026-05-01" },
      },
      registry
    );
    expect(id.jobId).toBe("org/repo--sre-health-check--2026-05-01");
  });

  it("throws for sre-health-check without data.dedup_key", () => {
    expect(() =>
      buildJobIdentity(
        { ...base, role: "sre-health-check", data: {} },
        registry
      )
    ).toThrow("data.dedup_key required");
  });

  it("throws for unknown role", () => {
    expect(() =>
      buildJobIdentity(
        { ...base, role: "nope" as AgentJob["role"] },
        registry
      )
    ).toThrow("Unknown role");
  });
});

describe("extractRole", () => {
  it("extracts renovate-triage from job id", () => {
    expect(extractRole("org/repo--renovate-triage--42", registry)).toBe(
      "renovate-triage"
    );
  });

  it("extracts renovate-fix from job id", () => {
    expect(extractRole("org/repo--renovate-fix--10", registry)).toBe(
      "renovate-fix"
    );
  });

  it("extracts revert from job id", () => {
    expect(extractRole("org/repo--revert", registry)).toBe("revert");
  });

  it("extracts validate from job id", () => {
    expect(extractRole("org/repo--validate", registry)).toBe("validate");
  });

  it("extracts execute-issue from job id", () => {
    expect(extractRole("org/repo--execute-issue--99", registry)).toBe(
      "execute-issue"
    );
  });

  it("extracts sre-alert from job id", () => {
    expect(extractRole("org/repo--sre-alert", registry)).toBe("sre-alert");
  });

  it("extracts sre-health-check from job id", () => {
    expect(
      extractRole("org/repo--sre-health-check--2026-05-01", registry)
    ).toBe("sre-health-check");
  });

  it("returns unknown for malformed id", () => {
    expect(extractRole("nope", registry)).toBe("unknown");
  });
});

describe("extractRole round-trip with buildJobIdentity", () => {
  const cases: { desc: string; job: AgentJob; expectedRole: string }[] = [
    {
      desc: "renovate-triage",
      job: { ...base, data: { pr_number: 42, head_sha: "abc" } },
      expectedRole: "renovate-triage",
    },
    {
      desc: "renovate-fix",
      job: {
        ...base,
        role: "renovate-fix",
        data: { pr_number: 10, head_sha: "def" },
      },
      expectedRole: "renovate-fix",
    },
    {
      desc: "revert",
      job: { ...base, role: "revert", data: {} },
      expectedRole: "revert",
    },
    {
      desc: "validate",
      job: { ...base, role: "validate", data: {} },
      expectedRole: "validate",
    },
    {
      desc: "execute-issue",
      job: { ...base, role: "execute-issue", data: { issue_number: 99 } },
      expectedRole: "execute-issue",
    },
    {
      desc: "sre-alert",
      job: { ...base, role: "sre-alert", data: { fingerprint: "fp-1" } },
      expectedRole: "sre-alert",
    },
    {
      desc: "sre-health-check",
      job: {
        ...base,
        role: "sre-health-check",
        data: { dedup_key: "2026-05-01" },
      },
      expectedRole: "sre-health-check",
    },
  ];

  for (const { desc, job, expectedRole } of cases) {
    it(`${desc}: extractRole recovers registry key from buildJobIdentity output`, () => {
      const identity = buildJobIdentity(job, registry);
      expect(extractRole(identity.jobId, registry)).toBe(expectedRole);
    });
  }
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ts/agent-queue-worker && npx vitest run src/job/identity.test.ts` Expected: Failures due to old identity function signatures

- [ ] **Step 3: Update identity.ts**

Replace `ts/agent-queue-worker/src/job/identity.ts` with:

```ts
import type { RoleRegistry } from "../roles/registry.js";
import type { AgentJob } from "./schema.js";

export interface JobIdentity {
  jobId: string;
  role: string;
  repo: string;
}

export function buildJobIdentity(
  job: AgentJob,
  registry: RoleRegistry
): JobIdentity {
  const roleDef = registry.get(job.role);
  const jobId = roleDef.buildIdentity(job.repo, job.data);
  return {
    jobId,
    role: job.role,
    repo: job.repo,
  };
}

export function extractRole(jobId: string, registry: RoleRegistry): string {
  const firstSep = jobId.indexOf("--");
  if (firstSep === -1) return "unknown";
  const afterRepo = jobId.substring(firstSep + 2);

  for (const name of registry.names()) {
    if (afterRepo === name || afterRepo.startsWith(`${name}--`)) {
      return name;
    }
  }

  return "unknown";
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/job/identity.test.ts` Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add ts/agent-queue-worker/src/job/identity.ts ts/agent-queue-worker/src/job/identity.test.ts
git commit -m "refactor(agent-queue-worker): update identity to use buildIdentity(repo, data)

Ref #<issue>"
```

______________________________________________________________________

### Task 6: Role tests — Rewrite roles.test.ts

**Files:**

- Rewrite: `ts/agent-queue-worker/src/roles/roles.test.ts`

- [ ] **Step 1: Replace roles.test.ts**

Replace `ts/agent-queue-worker/src/roles/roles.test.ts` with:

```ts
import type { Histogram } from "prom-client";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Config } from "../config.js";
import type { AgentJob } from "../job/schema.js";
import { createDefaultRegistry } from "./registry.js";
import type { JobState } from "./types.js";
import { resolveDuplicateAction } from "./types.js";

const mockConfig = {
  SRE_BATCH_MAX_SIZE: 50,
  SRE_BATCH_WINDOW_MS: 60_000,
  SRE_COOLDOWN_MS: 300_000,
  SRE_TRIAGE_SUPPRESS_S: 3600,
} as Config;

const mockHistogram = { observe: vi.fn() } as unknown as Histogram;

const registry = createDefaultRegistry(mockConfig, mockHistogram);

const STATES: JobState[] = ["waiting", "prioritized", "active", "delayed"];

function makeJob(
  role: string,
  data: Record<string, unknown> = {}
): AgentJob {
  return {
    role: role as AgentJob["role"],
    repo: "org/repo",
    event_type: "test",
    priority: 5,
    data,
  };
}

describe("duplicate resolution", () => {
  describe("renovate-triage (default strategy)", () => {
    const def = registry.get("renovate-triage");
    const job = makeJob("renovate-triage", {
      pr_number: 1,
      head_sha: "abc",
    });

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("replaces when prioritized", () => {
      expect(resolveDuplicateAction(def, job, job, "prioritized")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("renovate-fix (default strategy)", () => {
    const def = registry.get("renovate-fix");
    const job = makeJob("renovate-fix", {
      pr_number: 10,
      head_sha: "def",
    });

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("replaces when prioritized", () => {
      expect(resolveDuplicateAction(def, job, job, "prioritized")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("revert (default strategy)", () => {
    const def = registry.get("revert");
    const job = makeJob("revert");

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("validate (default strategy)", () => {
    const def = registry.get("validate");
    const job = makeJob("validate");

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });
  });

  describe("execute-issue (always discard)", () => {
    const def = registry.get("execute-issue");
    const job = makeJob("execute-issue", { issue_number: 1 });

    for (const state of STATES) {
      it(`discards when ${state}`, () => {
        expect(resolveDuplicateAction(def, job, job, state)).toEqual({
          action: "discard",
        });
      });
    }
  });

  describe("sre-alert (always buffer)", () => {
    const def = registry.get("sre-alert");
    const job = makeJob("sre-alert", { fingerprint: "fp-1" });

    for (const state of STATES) {
      it(`buffers when ${state}`, () => {
        expect(resolveDuplicateAction(def, job, job, state)).toEqual({
          action: "buffer",
        });
      });
    }
  });

  describe("sre-health-check (replace or discard)", () => {
    const def = registry.get("sre-health-check");
    const job = makeJob("sre-health-check", { dedup_key: "d1" });

    it("replaces when waiting", () => {
      expect(resolveDuplicateAction(def, job, job, "waiting")).toEqual({
        action: "replace",
      });
    });

    it("replaces when prioritized", () => {
      expect(resolveDuplicateAction(def, job, job, "prioritized")).toEqual({
        action: "replace",
      });
    });

    it("discards when active", () => {
      expect(resolveDuplicateAction(def, job, job, "active")).toEqual({
        action: "discard",
      });
    });

    it("discards when delayed", () => {
      expect(resolveDuplicateAction(def, job, job, "delayed")).toEqual({
        action: "discard",
      });
    });
  });

  describe("sre-alert bufferKey", () => {
    it("provides bufferKey", () => {
      const def = registry.get("sre-alert");
      expect(def.bufferKey!("org/repo--sre-alert")).toBe(
        "agent:sre-alerts:org/repo--sre-alert"
      );
    });
  });

  describe("sre-alert cooldown", () => {
    it("has 5-minute cooldown between sessions", () => {
      const def = registry.get("sre-alert");
      expect(def.cooldownMs).toBe(300_000);
    });
  });
});

describe("role timeouts", () => {
  it("all timeouts are positive", () => {
    for (const role of registry.names()) {
      expect(registry.get(role).timeoutMs).toBeGreaterThan(0);
    }
  });

  it("renovate-triage is fastest (ephemeral PR check)", () => {
    const triage = registry.get("renovate-triage").timeoutMs;
    for (const role of [
      "renovate-fix",
      "validate",
      "execute-issue",
      "sre-alert",
      "sre-health-check",
    ]) {
      expect(triage).toBeLessThan(registry.get(role).timeoutMs);
    }
  });

  it("execute-issue has longest timeout (full pipeline)", () => {
    const execute = registry.get("execute-issue").timeoutMs;
    for (const role of [
      "renovate-triage",
      "renovate-fix",
      "validate",
      "sre-alert",
      "sre-health-check",
      "revert",
    ]) {
      expect(execute).toBeGreaterThan(registry.get(role).timeoutMs);
    }
  });
});

describe("registry", () => {
  it("throws for unknown role", () => {
    expect(() => registry.get("nope")).toThrow("Unknown role");
  });

  it("has all expected roles", () => {
    expect(registry.names().sort()).toEqual([
      "execute-issue",
      "renovate-fix",
      "renovate-triage",
      "revert",
      "sre-alert",
      "sre-health-check",
      "validate",
    ]);
  });
});

describe("sre-alert getJobDelay", () => {
  const def = registry.get("sre-alert");

  it("returns batch window from config", () => {
    const job = makeJob("sre-alert", { fingerprint: "fp-1" });
    expect(def.getJobDelay!(job)).toBe(60_000);
  });

  it("returns per-job override when present", () => {
    const job = makeJob("sre-alert", {
      fingerprint: "fp-1",
      batch_window_ms: 30_000,
    });
    expect(def.getJobDelay!(job)).toBe(30_000);
  });

  it("caps per-job override at 6 hours", () => {
    const job = makeJob("sre-alert", {
      fingerprint: "fp-1",
      batch_window_ms: 999_999_999,
    });
    expect(def.getJobDelay!(job)).toBe(21_600_000);
  });

  it("clamps negative per-job override to 0", () => {
    const job = makeJob("sre-alert", {
      fingerprint: "fp-1",
      batch_window_ms: -1,
    });
    expect(def.getJobDelay!(job)).toBe(0);
  });

  it("returns 0 when batch window is 0", () => {
    const zeroConfig = { ...mockConfig, SRE_BATCH_WINDOW_MS: 0 } as Config;
    const zeroHistogram = { observe: vi.fn() } as unknown as Histogram;
    const zeroRegistry = createDefaultRegistry(zeroConfig, zeroHistogram);
    const def2 = zeroRegistry.get("sre-alert");
    const job = makeJob("sre-alert", { fingerprint: "fp-1" });
    expect(def2.getJobDelay!(job)).toBe(0);
  });
});

describe("sre-alert cooldownMs from config", () => {
  it("reads cooldownMs from SRE_COOLDOWN_MS config", () => {
    const def = registry.get("sre-alert");
    expect(def.cooldownMs).toBe(300_000);
  });

  it("respects custom cooldown value", () => {
    const customConfig = {
      ...mockConfig,
      SRE_COOLDOWN_MS: 120_000,
    } as Config;
    const customRegistry = createDefaultRegistry(
      customConfig,
      mockHistogram
    );
    const def = customRegistry.get("sre-alert");
    expect(def.cooldownMs).toBe(120_000);
  });
});

describe("sre-alert drainBuffer", () => {
  const def = registry.get("sre-alert");
  const job = makeJob("sre-alert", {
    fingerprint: "fp-1",
    alertname: "HighCPU",
  });

  beforeEach(() => {
    vi.mocked(mockHistogram.observe).mockClear();
  });

  it("includes original + buffered in alerts array", async () => {
    const items = [
      JSON.stringify({ alertname: "A1" }),
      JSON.stringify({ alertname: "A2" }),
      JSON.stringify({ alertname: "A3" }),
      JSON.stringify({ alertname: "A4" }),
      JSON.stringify({ alertname: "A5" }),
    ];
    const mockRedis = { eval: vi.fn().mockResolvedValue(items) } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(6);
    expect(result.data?.alerts).toHaveLength(6);
    expect((result.data?.alerts as any[])[0]).toEqual({
      fingerprint: "fp-1",
      alertname: "HighCPU",
    });
    expect((result.data?.alerts as any[])[1]).toEqual({ alertname: "A1" });
  });

  it("returns single-element alerts array when buffer empty", async () => {
    const mockRedis = {
      eval: vi.fn().mockResolvedValue([]),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(1);
    expect(result.data?.alerts).toEqual([
      { fingerprint: "fp-1", alertname: "HighCPU" },
    ]);
  });

  it("returns single-element alerts array when buffer null", async () => {
    const mockRedis = {
      eval: vi.fn().mockResolvedValue(null),
    } as any;

    const result = await def.drainBuffer!("job1", job, mockRedis);

    expect(mockHistogram.observe).toHaveBeenCalledWith(1);
    expect(result.data?.alerts).toEqual([
      { fingerprint: "fp-1", alertname: "HighCPU" },
    ]);
  });
});
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/roles/roles.test.ts` Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/roles/roles.test.ts
git commit -m "test(agent-queue-worker): rewrite role tests for v2 schema

Ref #<issue>"
```

______________________________________________________________________

### Task 7: Middleware — Return detailed validation errors

**Files:**

- Modify: `ts/agent-queue-worker/src/http/middleware.ts`

- [ ] **Step 1: Update parseAndValidate error response and SafeParseResult type**

In `ts/agent-queue-worker/src/http/middleware.ts`:

Change the `SafeParseResult` interface from:

```ts
interface SafeParseResult<T> {
  success: boolean;
  data?: T;
  error?: { issues: Array<{ path: PropertyKey[] }> };
}
```

To:

```ts
interface SafeParseResult<T> {
  success: boolean;
  data?: T;
  error?: { issues: Array<{ path: PropertyKey[]; message: string }> };
}
```

Change the error response in `parseAndValidate` from:

```ts
    json(res, 400, {
      ...responseBase,
      reason: "invalid_request",
      fields: parsed.error?.issues.map((i) => i.path.join(".")),
    });
```

To:

```ts
    json(res, 400, {
      ...responseBase,
      reason: "invalid_request",
      errors: parsed.error?.issues.map((i) => ({
        field: i.path.join("."),
        message: i.message,
      })),
    });
```

- [ ] **Step 2: Commit**

```bash
git add ts/agent-queue-worker/src/http/middleware.ts
git commit -m "feat(agent-queue-worker): return field paths and messages in validation errors

Ref #<issue>"
```

______________________________________________________________________

### Task 8: Routes — Update field access and remove identity catch block

**Files:**

- Modify: `ts/agent-queue-worker/src/http/routes.ts`

- [ ] **Step 1: Update imports**

In `ts/agent-queue-worker/src/http/routes.ts`:

Change:

```ts
import { sreTriagedKey } from "../roles/sre-role.js";
```

To:

```ts
import { sreTriagedKey } from "../roles/sre-alert-role.js";
```

- [ ] **Step 2: Update SRE alert suppression check**

Change:

```ts
  if (
    data.role === "sre" &&
    data.payload?.trigger === "alert" &&
    data.payload?.fingerprint
  ) {
    const fpKey = sreTriagedKey(data.repo, String(data.payload.fingerprint));
```

To:

```ts
  if (data.role === "sre-alert" && data.data?.fingerprint) {
    const fpKey = sreTriagedKey(data.repo, String(data.data.fingerprint));
```

- [ ] **Step 3: Remove identity/role try-catch block**

Replace:

```ts
  let identity: ReturnType<typeof buildJobIdentity>;
  let roleDef: ReturnType<RouteDeps["registry"]["get"]>;
  try {
    identity = buildJobIdentity(data, deps.registry);
    roleDef = deps.registry.get(data.role);
  } catch (err) {
    logger.warn("Job identity/role validation failed", {
      role: data.role,
      error: err instanceof Error ? err.message : String(err),
    });
    return json(res, 400, {
      added: false,
      reason: "invalid_request",
    });
  }
  const jobId = identity.jobId;
```

With:

```ts
  const identity = buildJobIdentity(data, deps.registry);
  const roleDef = deps.registry.get(data.role);
  const jobId = identity.jobId;
```

- [ ] **Step 4: Update buffer data field references**

In the `shouldBuffer` block, change:

```ts
      const shouldBuffer =
        roleDef.bufferKey && data.payload?.trigger === "alert";
      if (shouldBuffer) {
        const bufKey = roleDef.bufferKey!(jobId);
        await deps.redis.rpush(bufKey, JSON.stringify(data.payload));
```

To:

```ts
      const shouldBuffer = !!roleDef.bufferKey;
      if (shouldBuffer) {
        const bufKey = roleDef.bufferKey!(jobId);
        await deps.redis.rpush(bufKey, JSON.stringify(data.data));
```

In the duplicate "buffer" action block, change:

```ts
        await deps.redis.rpush(bufKey, JSON.stringify(data.payload));
```

To:

```ts
        await deps.redis.rpush(bufKey, JSON.stringify(data.data));
```

- [ ] **Step 5: Commit**

```bash
git add ts/agent-queue-worker/src/http/routes.ts
git commit -m "refactor(agent-queue-worker): update routes for v2 schema field paths

Ref #<issue>"
```

______________________________________________________________________

### Task 9: Processor — Update field destructuring

**Files:**

- Modify: `ts/agent-queue-worker/src/processor.ts`

- [ ] **Step 1: Update process() destructuring**

In `ts/agent-queue-worker/src/processor.ts`, change:

```ts
    const { role, repo, pr_number, head_sha } = job.data;
    const roleDef = this.registry.get(role);
    const timeout = roleDef.timeoutMs;
    const timeoutSec = Math.ceil(timeout / 1000);
    const fields = { jobId: job.id!, role, repo, pr: pr_number, sha: head_sha };
```

To:

```ts
    const { role, repo } = job.data;
    const roleDef = this.registry.get(role);
    const timeout = roleDef.timeoutMs;
    const timeoutSec = Math.ceil(timeout / 1000);
    const fields = { jobId: job.id!, role, repo };
```

- [ ] **Step 2: Commit**

```bash
git add ts/agent-queue-worker/src/processor.ts
git commit -m "refactor(agent-queue-worker): update processor field access for v2 schema

Ref #<issue>"
```

______________________________________________________________________

### Task 10: Lifecycle — Update alert data access paths

**Files:**

- Modify: `ts/agent-queue-worker/src/queue/lifecycle.ts`

- [ ] **Step 1: Update import**

Change:

```ts
import { sreTriagedKey } from "../roles/sre-role.js";
```

To:

```ts
import { sreTriagedKey } from "../roles/sre-alert-role.js";
```

- [ ] **Step 2: Update completed handler alert field access**

Change:

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
```

To:

```ts
    if (job.data.role === "sre-alert") {
      const suppressTtl = Number(
        job.data.data?.triage_suppress_s ?? config.SRE_TRIAGE_SUPPRESS_S
      );
      const fingerprints = new Set<string>();

      if (job.data.data?.fingerprint) {
        fingerprints.add(String(job.data.data.fingerprint));
      }
      const processedAlerts = job.data.data?.alerts as
        | Array<Record<string, unknown>>
        | undefined;
```

- [ ] **Step 3: Update drain buffer access**

Change:

```ts
      const drainedData = await roleDef.drainBuffer(job.id!, job.data, redis);
      const alerts = drainedData.payload?.alerts as unknown[] | undefined;
```

To:

```ts
      const drainedData = await roleDef.drainBuffer(job.id!, job.data, redis);
      const alerts = drainedData.data?.alerts as unknown[] | undefined;
```

- [ ] **Step 4: Commit**

```bash
git add ts/agent-queue-worker/src/queue/lifecycle.ts
git commit -m "refactor(agent-queue-worker): update lifecycle alert access for v2 schema

Ref #<issue>"
```

______________________________________________________________________

### Task 11: Lifecycle tests — Update test data shapes

**Files:**

- Modify: `ts/agent-queue-worker/src/queue/lifecycle.test.ts`

- [ ] **Step 1: Update all test job data to use `data` instead of `payload` and new role names**

In `ts/agent-queue-worker/src/queue/lifecycle.test.ts`:

Update `createMockDeps` — change drainBuffer mock return value:

```ts
  const drainBuffer = vi.fn().mockResolvedValue({
    role: "sre-alert",
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    data: { fingerprint: "fp-1" },
  });
```

Update the triaged marker test job:

```ts
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
    };
```

Update the alerts array test job:

```ts
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-main",
          alerts: [{ fingerprint: "fp-a1" }, { fingerprint: "fp-a2" }],
        },
      },
      opts: {},
      attemptsMade: 0,
    };
```

Update the triage_suppress_s override test job:

```ts
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-1",
          triage_suppress_s: 7200,
        },
      },
      opts: {},
      attemptsMade: 0,
    };
```

Update the non-alert (health-check) test job:

```ts
    const job = {
      id: "org/repo--sre-health-check--d1",
      data: {
        role: "sre-health-check",
        repo: "org/repo",
        event_type: "schedule",
        priority: 5,
        data: { dedup_key: "d1" },
      },
      opts: {},
      attemptsMade: 0,
    };
```

Update the dedup fingerprints test job:

```ts
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: {
          fingerprint: "fp-dup",
          alerts: [{ fingerprint: "fp-dup" }, { fingerprint: "fp-unique" }],
        },
      },
      opts: {},
      attemptsMade: 0,
    };
```

Update the unknown role test job:

```ts
    const job = {
      id: "org/repo--bad-job",
      data: {
        role: "bad",
        repo: "org/repo",
        event_type: "unknown",
        priority: 5,
        data: {},
      },
      opts: {},
      attemptsMade: 0,
    };
```

Update the pipeline error test job:

```ts
    const job = {
      id: "org/repo--sre-alert",
      data: {
        role: "sre-alert",
        repo: "org/repo",
        event_type: "alert",
        priority: 5,
        data: { fingerprint: "fp-1" },
      },
      opts: {},
      attemptsMade: 0,
    };
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/queue/lifecycle.test.ts` Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/queue/lifecycle.test.ts
git commit -m "test(agent-queue-worker): update lifecycle tests for v2 schema

Ref #<issue>"
```

______________________________________________________________________

### Task 12: Routes tests — Update test payloads

**Files:**

- Modify: `ts/agent-queue-worker/src/http/routes.test.ts`

- [ ] **Step 1: Update all test payloads and assertions**

In `ts/agent-queue-worker/src/http/routes.test.ts`:

Update `jobData`:

```ts
const jobData = {
  role: "renovate-triage" as const,
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  data: { pr_number: 42, head_sha: "abc", action: "opened" },
  dispatch_state: "dispatched" as const,
  dispatched_at: "2026-01-01T00:00:00Z",
};
```

In handleGetJob tests, update assertions — remove `expect(body.pr_number).toBe(42)` and add:

```ts
    expect(body.data).toEqual({ pr_number: 42, head_sha: "abc", action: "opened" });
```

Remove the entire `handleAddJob validation` describe block — schema validation now catches all field issues at parse time, so the identity/role throw tests are obsolete.

Update `handleAddJob suppression` — change `sreAlert`:

```ts
  const sreAlert = {
    role: "sre-alert" as const,
    repo: "org/repo",
    event_type: "alert",
    priority: 5,
    data: { fingerprint: "fp-abc123" },
  };
```

Update the `makeDeps` mock registry:

```ts
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 900_000,
          cooldownMs: 300_000,
          jobOptions: { attempts: 1 },
          buildIdentity: (repo: string) => `${repo}--sre-alert`,
          getJobDelay: () => 0,
        }),
      },
```

Update the "does not suppress non-SRE role" test request:

```ts
    const req = mockReq({
      role: "renovate-triage",
      repo: "org/repo",
      event_type: "pull_request",
      priority: 5,
      data: { pr_number: 1, head_sha: "abc" },
    });
    const deps = makeDeps({
      redis: { exists: vi.fn().mockResolvedValue(1) },
      registry: {
        get: vi.fn().mockReturnValue({
          timeoutMs: 120_000,
          jobOptions: {},
          buildIdentity: (repo: string) => `${repo}--renovate-triage--1`,
          getJobDelay: () => 0,
        }),
      },
    });
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `cd ts/agent-queue-worker && npx vitest run src/http/routes.test.ts` Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/http/routes.test.ts
git commit -m "test(agent-queue-worker): update routes tests for v2 schema

Ref #<issue>"
```

______________________________________________________________________

### Task 13: Full test suite + typecheck

**Files:** All

- [ ] **Step 1: Run full typecheck**

Run: `cd ts/agent-queue-worker && npx tsc --noEmit` Expected: No errors

- [ ] **Step 2: Run full test suite**

Run: `cd ts/agent-queue-worker && npx vitest run` Expected: All tests PASS

- [ ] **Step 3: Run lint**

Run: `cd ts/agent-queue-worker && npx biome check src/` Expected: No errors (or only auto-fixable formatting)

- [ ] **Step 4: Fix any issues found**

If typecheck or tests fail, fix the issues.

- [ ] **Step 5: Build**

Run: `cd ts/agent-queue-worker && npm run build` Expected: Clean build

- [ ] **Step 6: Commit any fixes**

```bash
git add <fixed-files>
git commit -m "fix(agent-queue-worker): resolve typecheck/test issues from v2 migration

Ref #<issue>"
```

______________________________________________________________________

### Task 14: Bump version

**Files:**

- Modify: `ts/agent-queue-worker/package.json`

- [ ] **Step 1: Bump version to 3.0.0**

This is a breaking API change. Bump the major version in `ts/agent-queue-worker/package.json`.

- [ ] **Step 2: Commit**

```bash
git add ts/agent-queue-worker/package.json
git commit -m "chore(agent-queue-worker): bump to v3.0.0 for schema v2 breaking change

Ref #<issue>"
```
