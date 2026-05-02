# SRE Alert Batching: Observability & Configurability

**Issue:** #1184 **Date:** 2026-05-02 **Status:** Approved

## Summary

Improve the existing SRE alert batching with configurable limits, a batch-size histogram metric, a deliberate batching window for cold-start scenarios, and consistent field naming. The core batching mechanism (identity collapsing + Redis list buffer + atomic Lua drain) is already in place.

## Goals

1. Configurable batch cap — no more hardcoded `-50` LTRIM
1. Configurable batch window — first alert delays job by N ms to collect a batch before dispatching
1. Histogram metric for batch-size distribution (Grafana capacity planning)
1. Field rename `buffered_alerts` → `alerts` for consistency

## Design

### 1. Config (`src/config.ts`)

Add two new fields to `ConfigSchema`:

```ts
SRE_BATCH_MAX_SIZE: z.coerce.number().int().min(1).default(50)
SRE_BATCH_WINDOW_MS: z.coerce.number().int().min(0).default(60_000)
```

- `SRE_BATCH_MAX_SIZE` — max alerts retained in Redis buffer (LTRIM cap)
- `SRE_BATCH_WINDOW_MS` — delay in ms before first alert-triggered SRE job activates (batching window). Set 0 to disable.

### 2. Metrics (`src/metrics.ts`)

New histogram:

```ts
export const sreBatchSize = new Histogram({
  name: "agent_sre_batch_size",
  help: "Number of alerts drained per SRE batch",
  buckets: [1, 5, 10, 20, 50],
  registers: [registry],
});
```

No labels — only SRE role uses this metric. Passed as parameter to `createSreRole` for testability rather than imported directly.

### 3. SRE Role Factory (`src/roles/sre-role.ts`)

Convert `sreRole` from a plain object export to a factory:

```ts
export function createSreRole(config: Config, batchSizeHistogram: Histogram): RoleDefinition
```

**Closed-over dependencies:**

- `config.SRE_BATCH_MAX_SIZE` — available for future drain-side capping
- `batchSizeHistogram` — observed in `drainBuffer` with `items.length`

**Changes:**

- `drainBuffer`: after drain, call `batchSizeHistogram.observe(items.length)`. Only observe when items > 0.
- `drainBuffer`: rename `buffered_alerts` → `alerts` in returned payload
- New method `getJobDelay(job)`: returns `config.SRE_BATCH_WINDOW_MS` when `payload.trigger === "alert"`, `0` otherwise

### 4. RoleDefinition Interface (`src/roles/types.ts`)

**Add `"delayed"` to `JobState` union:** Currently `"waiting" | "prioritized" | "active"`. Delayed jobs exist in a special Redis sorted set and `getJob()` finds them with state `"delayed"`. SRE alert `onDuplicate` already handles this correctly (returns buffer regardless of state), but the type should be accurate.

**Add optional method:**

```ts
getJobDelay?(job: AgentJob): number;
```

Returns milliseconds to delay a newly created job. Used by `routes.ts` when adding jobs to BullMQ. Defaults to 0 if not implemented.

### 5. Routes (`src/http/routes.ts`)

Three changes:

**LTRIM cap:** Replace hardcoded `-50` with `-config.SRE_BATCH_MAX_SIZE`. Config is available via `RouteDeps` — add `config` to `RouteDeps` interface. Remove redundant `config` declaration from `ServerDeps` in `server.ts` (it will inherit from `RouteDeps`).

**Batch window:** When adding a new job (not buffered/replaced), call `roleDef.getJobDelay?.(data) ?? 0` and pass as `delay` option to `queue.add()`.

**Lua script comment:** Add a comment to `ATOMIC_UPDATE_IF_WAITING_LUA` documenting that it does not check the BullMQ delayed sorted set. This is safe because no `onDuplicate` implementation returns `replace` for delayed jobs (SRE alerts always return `buffer`; all other roles discard non-waiting/prioritized states). If a future role needs to replace delayed jobs, the Lua script must be extended
to check the delayed set.

### 6. Lifecycle (`src/queue/lifecycle.ts`)

Two changes:

**LTRIM cap:** Replace hardcoded `-50` in the fallback re-push path (line 71) with `config.SRE_BATCH_MAX_SIZE`. Config already available via `LifecycleDeps`.

**Field rename:** Update `buffered_alerts` reference on line 45 to `alerts`.

**Re-queue delay:** No delay on re-queued jobs. Alerts already waited through previous job's full processing time.

### 7. Registry (`src/roles/registry.ts`)

`createDefaultRegistry()` signature changes:

```ts
export function createDefaultRegistry(config: Config, batchSizeHistogram: Histogram): RoleRegistry
```

Passes config + histogram to `createSreRole()`. Other roles unchanged.

### 8. Helm Values (`cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml`)

Add to worker container env block:

```yaml
SRE_BATCH_MAX_SIZE: "50"
SRE_BATCH_WINDOW_MS: "60000"
```

### 9. Call Chain Impact

```text
index.ts
  → loadConfig()
  → create sreBatchSize histogram (already in metrics.ts module scope)
  → createDefaultRegistry(config, sreBatchSize)
    → createSreRole(config, sreBatchSize)
  → new Processor(config, redis, registry)  // unchanged
  → setupLifecycle({...})                   // unchanged, config already threaded
  → createServer({..., config})             // config added to RouteDeps
```

Callers of `drainBuffer` (`processor.ts:201`, `lifecycle.ts:44`) don't change — signature stays `(jobId, data, redis)`. Dependencies are closed over in the factory.

## Flow Diagram

```text
Alert 1 arrives → no existing job → queue.add(delay=60s) → job in "delayed" state
Alert 2 arrives (t+10s) → getJob finds delayed job → onDuplicate → buffer → RPUSH + LTRIM
Alert 3 arrives (t+30s) → getJob finds delayed job → onDuplicate → buffer → RPUSH + LTRIM
  ... 60s expires → BullMQ promotes job to "waiting" → worker picks up ...
Job activates → drainBuffer() → LRANGE+DEL atomic → histogram.observe(2) (buffered only)
  → payload.alerts = [alert2, alert3] (2 buffered; original alert is in job data)
  → dispatch to n8n with 3 alerts total (1 trigger + 2 buffered)
  ... agent triages all 3 ...
Job completes → lifecycle drain → more alerts? → re-queue immediately (no delay)
```

## Testing Plan

### Unit Tests

1. **`drainBuffer` histogram observation:** Buffer 5 items, drain, verify histogram observed with value 5
1. **`drainBuffer` field name:** Verify returned payload uses `alerts` not `buffered_alerts`
1. **`drainBuffer` empty buffer:** Verify histogram NOT observed when 0 items
1. **`getJobDelay` alert trigger:** Returns `SRE_BATCH_WINDOW_MS` value
1. **`getJobDelay` scheduled:** Returns 0
1. **LTRIM cap:** Verify `SRE_BATCH_MAX_SIZE=3` limits buffer to 3 items

### Existing Test Updates

- `roles.test.ts`: Update `createDefaultRegistry()` call to pass mock config + histogram

### Integration

1. Verify `/metrics` endpoint includes `agent_sre_batch_size` buckets
1. Verify delayed job activates after configured window

## Files Changed

| File                                                                  | Change                                                           |
| --------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `ts/agent-queue-worker/src/config.ts`                                 | Add `SRE_BATCH_MAX_SIZE`, `SRE_BATCH_WINDOW_MS`                  |
| `ts/agent-queue-worker/src/metrics.ts`                                | Add `agent_sre_batch_size` histogram                             |
| `ts/agent-queue-worker/src/roles/types.ts`                            | Add `"delayed"` to `JobState`, add optional `getJobDelay` method |
| `ts/agent-queue-worker/src/roles/sre-role.ts`                         | Convert to factory, add histogram + delay + rename               |
| `ts/agent-queue-worker/src/roles/registry.ts`                         | Thread config + histogram to `createSreRole`                     |
| `ts/agent-queue-worker/src/http/routes.ts`                            | Config-ify LTRIM, add delay to `queue.add`                       |
| `ts/agent-queue-worker/src/queue/lifecycle.ts`                        | Config-ify LTRIM, rename field reference                         |
| `ts/agent-queue-worker/src/index.ts`                                  | Thread new deps through startup                                  |
| `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml` | Add env vars                                                     |
| `ts/agent-queue-worker/src/roles/roles.test.ts`                       | Update for factory, add new tests                                |

## Out of Scope

- Time-windowed batching at drain time (drain returns everything in buffer)
- Per-repo or per-alert-type batch config
- Grafana dashboard creation (follow-up)
