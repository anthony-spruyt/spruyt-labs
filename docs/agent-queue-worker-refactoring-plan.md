# Agent Queue Worker Refactoring Plan

## Context

The `ts/agent-queue-worker/src/` codebase works but has significant structural debt. `buildJobId` is an unmaintainable switch statement, `head_sha` is required when meaningless for many jobs, `Router` is a 374-line god class, `extractRole` is provably broken (returns SHA for validate/sre jobs). User wants: generic dedup keys (SHA, date, issue number, etc.) and extensibility without touching core
logic.

## Job Lifecycle (actual flow)

```text
n8n → POST /jobs → BullMQ decides:
  ├─ create new job (no match)
  ├─ replace waiting job (match waiting, newer data is better — default)
  ├─ enrich waiting job (match waiting, merge new data into existing — SRE alerts)
  └─ discard (match active or recently completed)
        ↓ (job goes active)
   worker dispatches back to n8n
        ↓
   n8n executes job
        ↓
   n8n → POST /jobs/:id/done (or job times out)
```

Key: n8n is both producer AND consumer. Worker is queue orchestrator. Completion via n8n callbacks — no in-worker pipeline needed.

**Duplicate handling** is role-driven. Current code discards all duplicates (keeps stale, throws away fresh). New behavior: default is **replace** (newer is better), roles can override to **enrich** (merge payloads) or **discard** (keep existing).

## Role Semantics

| Role                  | Purpose                       | Job ID (dedup)                      | onDuplicate         | Staleness   | Notes                                                                            |
| --------------------- | ----------------------------- | ----------------------------------- | ------------------- | ----------- | -------------------------------------------------------------------------------- |
| **triage**            | Renovate PR analysis          | `repo--triage--pr`                  | replace             | PR head SHA | SHA is payload, not identity                                                     |
| **fix**               | Renovate PR auto-fix          | `repo--fix--pr`                     | replace             | PR head SHA | Same as triage                                                                   |
| **validate**          | Post-merge main validation    | `repo--validate`                    | replace             | none        | Merge storm → one job, n8n resolves HEAD                                         |
| **execute**           | Implement issues, produce PRs | `repo--execute--issue`              | discard             | none        | One per issue, first wins                                                        |
| **sre** (alert)       | Alert triage in context       | `repo--sre-triage`                  | buffer (all states) | none        | RPUSH to sidecar list. On completion, drain + auto-queue if non-empty. See below |
| **sre** (scheduled)   | Periodic health check         | `repo--sre-health-check--dedup_key` | replace             | none        | dedup_key = date or window                                                       |
| **review** *(future)* | Review non-Renovate PRs       | `repo--review--pr`                  | replace             | PR head SHA | Slots into pr-role.ts factory                                                    |

Pattern: `repo--role[--qualifier]`. Qualifier is PR number, issue number, or dedup_key. Omitted when role is inherently singleton per repo (validate, sre-triage).

**Delimiter safety:** Repo field is `owner/repo` format (contains `/`). Role names and qualifiers never contain `--`. So `split('--')` unambiguously produces `[repo, role, ...qualifier]`. `buildJobIdentity` validates repo does not contain `--` as a defensive check.

SHA and fingerprint are **payload data, not identity**. Identity is the coarsest grain that makes sense for dedup — one job per PR, one per repo for validate, one per repo for SRE alert triage.

`pr-role.ts` factory covers triage, fix, and future review — all PR-bound, staleness via GitHub API.

**Superseding is eliminated.** With SHA removed from job IDs, duplicate handling (replace) naturally supersedes. No need for separate `supersedeOlderJobs` scan — it was compensating for SHA being in the ID.

**Revert jobs:** Currently handled as a special case in `buildJobId` (`payload.revert → repo--sha--revert--fix`). In the new design, revert is handled by the fix role — `buildIdentitySegments` checks `payload.revert` and uses `repo--fix--revert` as the job ID. Same factory, different qualifier. No separate role needed.

**SRE alert buffering (unified for all states):**

- SRE `onDuplicate` returns `{ action: "buffer" }` regardless of state (waiting, prioritized, or active). All alerts go to the same Redis list via RPUSH — concurrent-safe, no CAS needed.
- `bufferKey(jobId)` returns `agent:sre-alerts:${jobId}`.
- At dispatch time, processor calls `drainBuffer` which atomically pops all alerts (LRANGE + DEL in Lua — same pattern as completion drain) and merges into job payload.
- On SRE job completion, `worker.on("completed")` atomically drains buffer (LRANGE + DEL in Lua). If alerts found, auto-queues new SRE triage job with `queue.add()`. If concurrent `addJob` already created the same jobId, the `queue.add` catches the duplicate error — drained alerts are re-pushed to the buffer key so the next `drainBuffer` at dispatch time picks them up. No alert loss.
- Max 50 alerts per buffer (LTRIM after RPUSH). TTL = 1 hour. Excess alerts dropped with metric.

## New File Structure

```text
src/
  index.ts                    -- slim composition root (~40 lines)
  config.ts                   -- unchanged
  logger.ts                   -- unchanged
  metrics.ts                  -- add `action` label to dedupCounter (new metric name: agent_dedup_action_total)
  github.ts                   -- unchanged

  roles/
    registry.ts               -- RoleRegistry map + createDefaultRegistry()
    types.ts                  -- RoleDefinition interface
    pr-role.ts                -- factory for PR-bound roles (triage/fix now, review later)
    validate-role.ts
    execute-role.ts
    sre-role.ts

  job/
    identity.ts               -- JobIdentity type, buildJobIdentity(), extractRole()
    identity.test.ts          -- migrated+fixed tests
    schema.ts                 -- Zod schemas + inferred types (AgentJob, DoneRequest, FailRequest, JobResult)
    schema.test.ts            -- migrated schema tests

  http/
    server.ts                 -- createHttpServer() + route dispatch
    middleware.ts             -- readBody(), authenticate(), jsonResponse(), parseAndValidate()
    routes.ts                 -- all route handlers (health, jobs, callbacks, circuit)

  queue/
    guard.ts                  -- CircuitBreaker + RateLimiter (extracted from Router)
    processor.ts              -- dispatch + callback orchestration
    lifecycle.ts              -- worker events, queue depth, startup reconciliation
```

## Key Design Decisions

### 1. RoleDefinition interface (replaces buildJobId switch)

```typescript
// src/roles/types.ts
export type DuplicateAction =
  | { action: "replace" }                  // replace with incoming data (default)
  | { action: "buffer" }                   // RPUSH to sidecar list (SRE alerts — concurrent-safe)
  | { action: "discard" }                  // keep existing as-is

export interface RoleDefinition {
  readonly timeoutMs: number;
  buildIdentitySegments(job: AgentJobInput): string[];
  checkStaleness?(job: AgentJobInput, config: Config): Promise<StalenessResult>; // runs at processing time, replaces processor.ts:91-105
  onDuplicate?(existingData: AgentJob, incomingRequest: AgentJob, state: JobState): DuplicateAction;
  // existingData may contain processor-injected fields (dispatch_state, dispatched_at)
  // state = "waiting" | "prioritized" | "active" — role sees state, decides accordingly
  // undefined = default "replace" (for waiting/prioritized), "discard" (for active)
  bufferKey?(jobId: string): string;
  // Redis list key for buffered data. Required if onDuplicate returns "buffer".
  drainBuffer?(jobId: string, data: AgentJob, redis: Redis): Promise<AgentJob>;
  // merge buffered data into job payload at dispatch time
}
```

Adding new role = one file + `registry.register("rolename", def)`. No switch statements. Role name lives in the registry key, not on the definition (avoids disagreement).

**onDuplicate examples (receives state):**

- PR roles: no override → default `replace` for waiting/prioritized, `discard` for active
- SRE alert role: always returns `buffer` (regardless of state — alerts accumulate in Redis list)
- Execute role: always returns `discard` — issue-bound, one job per issue, first wins
- Validate role: no override → default `replace` for waiting/prioritized, `discard` for active

**`head_sha` requirement:** Optional at schema level, but PR-bound roles (triage/fix/review) validate its presence in `buildIdentitySegments` and `checkStaleness`. If absent, staleness check skips. Schema stays permissive; roles enforce their own requirements.

### 2. Generic dedup (replaces mandatory head_sha)

Schema changes:

- `head_sha` becomes `z.string().optional()`
- Add `dedup_key: z.string().min(1).optional()` -- explicit override

Each role's `buildIdentitySegments` uses whichever field is appropriate:

- PR roles: `repo`, role name, `pr_number`
- Validate: `repo`, "validate"
- Execute: `repo`, "execute", `issue_number`
- SRE alert: `repo`, "sre-triage"
- SRE scheduled: `repo`, "sre-health-check", `dedup_key`

### 3. Fixed extractRole

Current bug: returns last `--` segment, which is SHA for validate/sre jobs.

**Fix:** With new `repo--role[--qualifier]` format, role is always segment [1] (after repo). `extractRole` splits on `--` and returns segment [1]. No legacy format support needed — this is a breaking version change.

### 4. Router decomposition

- `parseAndValidate<T>(req, schema)` eliminates 3x repeated try/catch+safeParse
- Each route group in its own file
- Middleware extracted for reuse

### 5. Duplicate handling (addJob flow)

Current addJob: dedup match → always 409 discard (keeps stale, throws away fresh). New flow:

```typescript
const identity = buildJobIdentity(data, registry);
const roleDef = registry.get(data.role);

// Recently completed → reject
const completed = await redis.exists(`agent:completed:${identity.jobId}`);
if (completed) return json(res, 409, { added: false, reason: "recently_completed" });

// Existing job in queue? Check state and let role decide
const existingJob = await queue.getJob(identity.jobId);
if (existingJob) {
  const state = await existingJob.getState() as JobState;
  const defaultAction = (state === "waiting" || state === "prioritized")
    ? { action: "replace" as const }
    : { action: "discard" as const };
  const decision = roleDef.onDuplicate?.(existingJob.data, data, state) ?? defaultAction;

  if (decision.action === "discard") {
    return json(res, 409, { added: false, reason: state === "active" ? "active" : "deduplicated" });
  }
  if (decision.action === "buffer") {
    const bufKey = roleDef.bufferKey!(identity.jobId);
    await redis.rpush(bufKey, JSON.stringify(data.payload));
    await redis.ltrim(bufKey, -50, -1);  // keep latest 50
    await redis.expire(bufKey, 3600);
    metrics.dedupCounter.inc({ queue: "agent", role: data.role, action: "buffer" });
    return json(res, 202, { added: false, buffered: true, jobId: identity.jobId });
  }
  // "replace" — atomic Lua: check still waiting/prioritized, then HSET
  const merged = JSON.stringify({ ...existingJob.data, ...data });
  const updated = await atomicUpdateIfWaiting(redis, identity.jobId, merged, queuePrefix);
  if (updated) {
    metrics.dedupCounter.inc({ queue: "agent", role: data.role, action: "replace" });
    return json(res, 200, { added: false, replaced: true, jobId: identity.jobId });
  }
  // Job transitioned to active — fall through to create new
}

// Create new job — keep BullMQ jobId for idempotent add (catches concurrent race)
try {
  await queue.add(data.role, data, { jobId: identity.jobId, ... });
  await redis.zadd(rateKey, Date.now(), identity.jobId);  // rate counter only for new jobs
} catch (err) {
  // BullMQ rejects duplicate jobId — concurrent request won the race
  if (isDuplicateJobError(err)) {
    return json(res, 409, { added: false, reason: "deduplicated" });
  }
  throw err;
}
```

**Atomic state-checked update (Lua script):**

```lua
-- KEYS[1] = wait list:       {prefix}:{queueName}:wait
-- KEYS[2] = prioritized set: {prefix}:{queueName}:prioritized
-- KEYS[3] = paused list:     {prefix}:{queueName}:paused
-- KEYS[4] = job hash key:    {prefix}:{queueName}:{jobId}
-- ARGV[1] = serialized merged data
-- ARGV[2] = jobId
local inWait   = redis.call('LPOS', KEYS[1], ARGV[2])
local inPrio   = redis.call('ZSCORE', KEYS[2], ARGV[2])
local inPaused = redis.call('LPOS', KEYS[3], ARGV[2])
if inWait ~= false or inPrio ~= false or inPaused ~= false then
  redis.call('HSET', KEYS[4], 'data', ARGV[1])
  return 1
end
return 0
```

**Key design choices:**

- **Correct Lua for state check** — BullMQ doesn't store state as a hash field. Must check membership in wait list (LPOS), prioritized sorted set (ZSCORE), and paused list (LPOS). Requires passing BullMQ-prefixed keys. The non-atomic `getJob`+`getState` before the Lua is acceptable because the Lua re-validates state atomically — add a code comment explaining this.
- **Unified `onDuplicate` receives state** — role sees `waiting`, `prioritized`, or `active` and decides. SRE returns `buffer` for all states (alerts always buffered). PR roles return `replace` for waiting, default `discard` for active.
- **`buffer` action uses RPUSH** — concurrent-safe, no CAS needed. Framework handles RPUSH/LTRIM/EXPIRE. Role only provides `bufferKey()`.
- **`replace` merges at framework level** — `{ ...existingJob.data, ...data }` (shallow). Prevents roles from dropping internal fields. Document: replace is shallow, `payload` key is fully replaced by incoming data.
- **BullMQ `deduplication` option removed**, but `jobId` kept on `queue.add()` for idempotent catch of concurrent races.
- **Rate counter only on new jobs** — replace/buffer don't increment.
- **Buffer TTL = 1 hour** — prevents leaked lists on orphaned jobs. `drainBuffer` DELs key after draining.

### 6. Superseding eliminated

With SHA/fingerprint out of job IDs, `supersedeOlderJobs` is no longer needed. It existed to remove stale SHA-keyed waiting jobs when a new SHA arrived for the same PR. Now job ID is `repo--pr--role` — duplicate handling (replace) naturally covers this. Delete `supersedeOlderJobs` entirely.

## Implementation Order (4 sequential PRs)

### PR 1: Role registry + new job identity (structural)

- **Breaking version** — pause queue before deploy, flush `agent:*` and `agent:queue:agent:de:*` keys, resume
- Create `src/roles/` with registry + all role definitions (including revert in fix role)
- Create `src/job/identity.ts` with `buildJobIdentity()` and fixed `extractRole()`
- Create `src/job/schema.ts` (schemas + inferred types, single file)
- New job ID format: `repo--role[--qualifier]`
- Schema: `head_sha` optional, add `dedup_key`
- Delete old `buildJobId`, `extractRole`, old `src/types.ts`
- Keep existing BullMQ dedup + `supersedeOlderJobs` as fallback (both removed in PR 2, dead code after PR 1 — add TODO)
- Add Zod refinement: `repo: z.string().min(1).refine(r => !r.includes('--'), 'repo must not contain --')`
- New tests for all role identity segments
- New metric: `agent_dedup_action_total` with `action` label (replace/buffer/discard)

### PR 2: Generic duplicate handling + SRE buffering (behavioral)

- Remove BullMQ `deduplication` option, `deduplicated` event listener, and `supersedeOlderJobs`
- Implement `onDuplicate` with state parameter: SRE (buffer), execute (discard), default (replace/discard)
- Atomic Lua for replace: check LPOS(wait) + ZSCORE(prioritized), then HSET
- SRE alert buffering via Redis lists (RPUSH + LTRIM(50) + EXPIRE(3600))
- `drainBuffer` at dispatch time: LRANGE + DEL → merge into payload
- Auto-queue new SRE job on completion if buffer non-empty
- Rate counter only incremented for new jobs (not replace/buffer)
- Catch duplicate jobId on `queue.add()` for concurrent race safety
- Tests for all dedup strategies + SRE buffering

### PR 3: Decompose Router into http/ + queue/ modules

- Create `src/http/middleware.ts` with `parseAndValidate`
- Create `src/http/routes.ts` with all route handlers
- Create `src/http/server.ts` with route dispatch
- Create `src/queue/guard.ts` (circuit breaker + rate limiter)
- Delete old `src/routes.ts`

### PR 4: Extract queue lifecycle from index.ts

- Create `src/queue/lifecycle.ts`
- Move worker events, queue depth polling, startup reconciliation
- Slim `index.ts` to pure composition root

## Security Model Notes

- **`POST /jobs/:id/done`** — requires session token. Prevents compromised agents from completing another agent's job with fabricated results. Token is single-use (consumed on valid use via Lua CAS).
- **`POST /jobs/:id/fail`** — bearer auth only, no session token. Only n8n calls this. Fail just triggers retry, no security-sensitive state change. Bearer proves caller is n8n, that's sufficient.

## What stays unchanged

- `config.ts` -- clean, well-tested
- `logger.ts` -- 27 lines, fine
- `github.ts` -- consumed by PR role's checkStaleness, coupling is appropriate
- BullMQ queue options (dedup, backoff, retry) -- working correctly

## Verification

- `npm run test` passes after each PR
- `npm run typecheck` passes
- `extractRole` returns correct role for all new-format job IDs
- qa-validator before each commit
