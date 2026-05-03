# SRE Alert Batching: Observability, Configurability & Fingerprint Suppression

**Issue:** #1184 **Date:** 2026-05-02 **Revised:** 2026-05-03 **Status:** Approved

## Summary

Improve the existing SRE alert batching with configurable limits, a batch-size histogram metric, a deliberate batching window for cold-start scenarios, consistent field naming, and fingerprint-based suppression to eliminate redundant retriages. Incorporates quick-fix `2f5b47c` (cooldown mechanism) which resolved an alert storm that spawned 100+ sessions in 3 hours.

## Goals

1. Configurable batch cap — no more hardcoded `-50` LTRIM (`SRE_BATCH_MAX_SIZE`)
1. Configurable batch window — first alert delays job by N ms to collect a batch before dispatching (`SRE_BATCH_WINDOW_MS`, per-job overridable)
1. Configurable cooldown — make quick-fix's hardcoded 5-min cooldown configurable (`SRE_COOLDOWN_MS`)
1. Histogram metric for batch-size distribution (Grafana capacity planning)
1. Fingerprint-based suppression — don't retriage alerts already handled within a TTL window (`SRE_TRIAGE_SUPPRESS_S`, per-job overridable)
1. Field rename `buffered_alerts` → `alerts` for consistency

## Prior Art: Quick Fix 2f5b47c

The quick fix added `cooldownMs: 300_000` to `RoleDefinition` and `sreRole`, a completed-state buffer path in `routes.ts`, and cooldown delay in `lifecycle.ts`. These changes are **already deployed** and must be preserved. This spec builds on top of them.

## Per-Job Override Summary

| Parameter           | Per-job? | Payload field               | Config fallback         | Rationale                                    |
| ------------------- | :------: | --------------------------- | ----------------------- | -------------------------------------------- |
| `batch_window_ms`   | **Yes**  | `payload.batch_window_ms`   | `SRE_BATCH_WINDOW_MS`   | Different urgency per alert type             |
| `triage_suppress_s` | **Yes**  | `payload.triage_suppress_s` | `SRE_TRIAGE_SUPPRESS_S` | Different shelf life per alert type          |
| `batch_max_size`    |  **No**  | —                           | `SRE_BATCH_MAX_SIZE`    | Shared buffer, destructive LTRIM, safety cap |
| `cooldown_ms`       |  **No**  | —                           | `SRE_COOLDOWN_MS`       | Storm protection, caller must not bypass     |

Per-job values arrive in the `payload` record (`z.record(z.string(), z.unknown())`), requiring no schema changes.

## Design

### 1. Config (`src/config.ts`)

Add four new fields to `ConfigSchema`:

```ts
SRE_BATCH_MAX_SIZE: z.coerce.number().int().min(1).default(50),
SRE_BATCH_WINDOW_MS: z.coerce.number().int().min(0).default(60_000),
SRE_COOLDOWN_MS: z.coerce.number().int().min(0).default(300_000),
SRE_TRIAGE_SUPPRESS_S: z.coerce.number().int().min(0).default(3600),
```

- `SRE_BATCH_MAX_SIZE` — max alerts retained in Redis buffer (LTRIM cap)
- `SRE_BATCH_WINDOW_MS` — delay in ms before first alert-triggered SRE job activates (batching window). Set 0 to disable.
- `SRE_COOLDOWN_MS` — delay in ms after job completion before next session. Set 0 to disable (not recommended).
- `SRE_TRIAGE_SUPPRESS_S` — default TTL in seconds for triaged alert fingerprints. Set 0 to disable suppression.

### 2. Metrics (`src/metrics.ts`)

New histogram:

```ts
export const sreBatchSize = new Histogram({
  name: "agent_sre_batch_size",
  help: "Total alerts per SRE batch (trigger + buffered)",
  buckets: [1, 5, 10, 20, 50],
  registers: [registry],
});
```

New counter:

```ts
export const sreSuppressed = new Counter({
  name: "agent_sre_suppressed_total",
  help: "Alerts suppressed by fingerprint dedup",
  labelNames: ["role"] as const,
  registers: [registry],
});
```

`sreBatchSize` passed as parameter to `createSreRole` for testability. `sreSuppressed` imported directly in `routes.ts` (where suppression check runs), consistent with existing `metrics.*` usage in that file.

### 3. SRE Role Factory (`src/roles/sre-role.ts`)

Convert `sreRole` from a plain object export to a factory:

```ts
export function createSreRole(config: Config, batchSizeHistogram: Histogram): RoleDefinition
```

**Closed-over dependencies:**

- `config.SRE_COOLDOWN_MS` — replaces hardcoded `cooldownMs: 300_000`
- `config.SRE_BATCH_WINDOW_MS` — default for `getJobDelay`
- `batchSizeHistogram` — observed in `drainBuffer` with `items.length`

**Changes from current state:**

- `cooldownMs` reads from `config.SRE_COOLDOWN_MS` instead of hardcoded `300_000`
- `drainBuffer`: after drain, call `batchSizeHistogram.observe(items.length + 1)` (buffered + trigger alert = total batch size). Only observe when items > 0.
- `drainBuffer`: rename `buffered_alerts` → `alerts` in returned payload
- New method `getJobDelay(job)`: returns `Math.min(job.payload?.batch_window_ms ?? config.SRE_BATCH_WINDOW_MS, 21_600_000)` when `payload.trigger === "alert"`, `0` otherwise. 6-hour ceiling prevents indefinite delay from malformed payloads.

### 4. RoleDefinition Interface (`src/roles/types.ts`)

**Already done by quick fix:** `"delayed"` in `JobState`, `cooldownMs` on `RoleDefinition`.

**Add optional method:**

```ts
getJobDelay?(job: AgentJob): number;
```

Returns milliseconds to delay a newly created job. Used by `routes.ts` when adding jobs to BullMQ. Defaults to 0 if not implemented.

### 5. Routes (`src/http/routes.ts`)

Five changes:

**Fingerprint suppression (early check):** Before identity resolution, check if incoming SRE alert's fingerprint has been triaged:

```ts
if (data.payload?.trigger === "alert" && data.payload?.fingerprint) {
  const key = sreTriagedKey(data.repo, String(data.payload.fingerprint));
  const triaged = await deps.redis.exists(key);
  if (triaged) {
    metrics.sreSuppressed.inc({ role: data.role });
    return json(res, 200, { added: false, reason: "already_triaged" });
  }
}
```

Returns `200` (not `409`) because suppression is normal behavior, not an error. The alert was handled — nothing to do.

**TOCTOU note:** Two identical alerts arriving simultaneously can both pass `EXISTS` before either writes a triaged marker. This is benign — downstream dedup (`onDuplicate → buffer`) catches it, resulting in one extra buffered alert at worst, never duplicate processing. No atomic guard needed.

**LTRIM cap:** Replace both hardcoded `-50` (line 76 in completed-state path, line 133 in active/waiting path) with `-deps.config.SRE_BATCH_MAX_SIZE`. Add `config: Config` to `RouteDeps` interface.

**Batch window:** When adding a new job (fresh, not buffered/replaced), call `roleDef.getJobDelay?.(data) ?? 0` and pass as `delay` option to `queue.add()`.

**Cooldown in completed-state path:** Replace `roleDef.cooldownMs ?? 300_000` with `roleDef.cooldownMs ?? deps.config.SRE_COOLDOWN_MS` (the role now reads from config, but the fallback also uses config).

**Lua script comment:** Extend comment on `ATOMIC_UPDATE_IF_WAITING_LUA` documenting that it does not check the BullMQ delayed sorted set. This is safe because no `onDuplicate` implementation returns `replace` for delayed jobs.

### 6. Lifecycle (`src/queue/lifecycle.ts`)

Four changes:

**Triaged markers on completion:** After job completes, extract fingerprints from `job.data`. When the buffer was non-empty at processing time, `processor.ts:213-215` calls `job.updateData(dispatchData)`, so `job.data.payload.alerts` contains the drained alerts. When the buffer was empty, `drainBuffer` returns the original data reference (no `updateData` call), but the trigger alert's fingerprint
at `job.data.payload.fingerprint` is always available. The code handles both cases:

```ts
if (job.data.payload?.trigger === "alert") {
  const suppressTtl = Number(job.data.payload?.triage_suppress_s ?? config.SRE_TRIAGE_SUPPRESS_S);
  const fingerprints = new Set<string>();

  if (job.data.payload?.fingerprint) fingerprints.add(String(job.data.payload.fingerprint));
  const processedAlerts = job.data.payload?.alerts as Array<Record<string, unknown>> | undefined;
  if (processedAlerts) {
    for (const a of processedAlerts) {
      if (a.fingerprint) fingerprints.add(String(a.fingerprint));
    }
  }

  if (fingerprints.size > 0 && suppressTtl > 0) {
    try {
      const pipeline = redis.pipeline();
      for (const fp of fingerprints) {
        pipeline.set(sreTriagedKey(job.data.repo, fp), "1", "EX", suppressTtl);
      }
      await pipeline.exec();
    } catch (err) {
      logger.warn("Failed to write triaged markers", { jobId: job.id, error: String(err) });
    }
  }
}
```

This runs BEFORE the lifecycle drain, so only alerts actually processed by the agent get marked. Alerts that arrived during processing (lifecycle drain) are NOT marked — they'll be processed in the next session.

**LTRIM cap:** Replace hardcoded `-50` in fallback re-push path with `-config.SRE_BATCH_MAX_SIZE`.

**Field rename:** Update `buffered_alerts` reference to `alerts`.

**Keep cooldown:** No changes to existing cooldown delay logic (quick fix).

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
SRE_COOLDOWN_MS: "300000"
SRE_TRIAGE_SUPPRESS_S: "3600"
```

### 9. Server (`src/http/server.ts`)

Remove redundant `config: Config` from `ServerDeps` — it now inherits from `RouteDeps`.

### 10. n8n Workflow Update

Split AlertManager webhooks into individual alert dispatches. Each alert sent as a separate POST to the worker, carrying its own fingerprint. Worker batches them naturally via existing identity + buffer machinery.

**Before (current):**

```js
const payload = $input.first().json;
const alertname = payload.alerts?.[0]?.labels?.alertname || 'unknown';
const fingerprint = payload.alerts?.[0]?.fingerprint || Date.now().toString();
return [{ json: { /* single item, first alert only */ } }];
```

**After:**

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

- `.map()` over `payload.alerts` — one output item per alert
- `fingerprint` moved to top-level of payload (from `metaData`)
- Per-alert `priority` based on severity
- Optional `batch_window_ms` override (critical = 0 for immediate processing)
- `alert_payload` contains single alert JSON, not full webhook

### 11. Call Chain Impact

```text
index.ts
  -> loadConfig()  (now has 4 new SRE_ fields)
  -> sreBatchSize histogram already in metrics.ts module scope
  -> createDefaultRegistry(config, sreBatchSize)
    -> createSreRole(config, sreBatchSize)  (factory, closes over config+histogram)
  -> new Processor(redis, config, registry)  (unchanged -- already calls job.updateData after drain)
  -> setupLifecycle({...})                   (unchanged deps, new logic inside)
  -> createServer({..., config})             (config now in RouteDeps, removed from ServerDeps)
```

## Flow Diagrams

### Normal Alert Flow (with batch window)

```text
Alert 1 arrives -> fingerprint NOT triaged -> no existing job -> queue.add(delay=60s)
  -> job in "delayed" state
Alert 2 arrives (t+10s) -> fingerprint NOT triaged -> existing delayed job
  -> onDuplicate -> buffer -> RPUSH + LTRIM
Alert 3 arrives (t+30s) -> fingerprint NOT triaged -> existing delayed job
  -> onDuplicate -> buffer -> RPUSH + LTRIM
  ... 60s expires -> BullMQ promotes job to "waiting" -> worker picks up ...
Job activates -> processor drainBuffer() -> LRANGE+DEL atomic
  -> histogram.observe(3) (trigger + 2 buffered)
  -> payload.alerts = [alert2, alert3]
  -> job.updateData() persists drained data
  -> dispatch to n8n with 3 alerts total (1 trigger + 2 buffered)
  ... agent triages all 3 ...
Job completes -> lifecycle handler:
  (1) Write triaged markers: fp1, fp2, fp3 (TTL = triage_suppress_s)
  (2) Drain buffer for NEW alerts (arrived during processing)
  (3) If new alerts: re-queue with cooldown delay
```

### Fingerprint Suppression Flow

```text
t=0:00  HighCPU(abc) fires -> NOT triaged -> create job (delayed 60s)
t=0:05  OOMKilled(def) fires -> NOT triaged -> buffer
t=0:15  HighCPU(abc) fires again -> NOT triaged -> buffer (job still delayed)
        ... job activates, agent triages all 3 ...
t=5:00  Job completes -> write triaged: abc (TTL 1h), def (TTL 1h)
t=5:01  HighCPU(abc) fires -> IS triaged -> DISCARD (200, already_triaged)
t=5:01  OOMKilled(def) fires -> IS triaged -> DISCARD
t=5:02  DiskPressure(ghi) fires -> NOT triaged -> create new job
t=6:00  abc TTL expires -> next HighCPU fire creates new triage
```

### Cooldown After Completion

```text
Job completes -> lifecycle drain finds 3 new alerts
  -> re-queue with delay = SRE_COOLDOWN_MS (5 min)
  -> job enters "delayed" for 5 min
  -> new alerts arriving during cooldown -> buffer against delayed job
  -> cooldown expires -> job activates -> processes accumulated batch
```

## Testing Plan

### Unit Tests

1. **Config:** Defaults for all 4 SRE\_ fields, coercion, min constraints
1. **`drainBuffer` histogram observation:** Buffer 5 items, drain, verify histogram observed with value 5
1. **`drainBuffer` field name:** Verify returned payload uses `alerts` not `buffered_alerts`
1. **`drainBuffer` empty buffer:** Verify histogram NOT observed when 0 items
1. **`getJobDelay` alert trigger:** Returns `SRE_BATCH_WINDOW_MS` value
1. **`getJobDelay` alert with per-job override:** Returns `payload.batch_window_ms`
1. **`getJobDelay` scheduled:** Returns 0
1. **`cooldownMs`:** Reads from `config.SRE_COOLDOWN_MS`
1. **LTRIM cap:** Verify `SRE_BATCH_MAX_SIZE=3` limits buffer to 3 items (in routes context)

### Existing Test Updates

- `roles.test.ts`: Update `createDefaultRegistry()` call to pass mock config + histogram
- All existing tests must continue passing

### Integration

1. Verify `/metrics` endpoint includes `agent_sre_batch_size` buckets
1. Verify `/metrics` endpoint includes `agent_sre_suppressed_total`
1. Verify fingerprint suppression returns 200 with `already_triaged`
1. Verify delayed job activates after configured window

## Files Changed

| File                                                                  | Change                                                           |
| --------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `ts/agent-queue-worker/src/config.ts`                                 | Add 4 SRE config fields                                          |
| `ts/agent-queue-worker/src/config.test.ts`                            | Tests for new fields                                             |
| `ts/agent-queue-worker/src/metrics.ts`                                | Add histogram + counter                                          |
| `ts/agent-queue-worker/src/roles/types.ts`                            | Add `getJobDelay` method                                         |
| `ts/agent-queue-worker/src/roles/sre-role.ts`                         | Convert to factory, histogram, delay, rename, config cooldown    |
| `ts/agent-queue-worker/src/roles/registry.ts`                         | Thread config + histogram                                        |
| `ts/agent-queue-worker/src/roles/roles.test.ts`                       | Update for factory, add new tests                                |
| `ts/agent-queue-worker/src/http/routes.ts`                            | Fingerprint suppression, config LTRIM, batch window, Lua comment |
| `ts/agent-queue-worker/src/http/server.ts`                            | Remove redundant config from ServerDeps                          |
| `ts/agent-queue-worker/src/queue/lifecycle.ts`                        | Triaged markers, config LTRIM, field rename                      |
| `ts/agent-queue-worker/src/index.ts`                                  | Thread new deps                                                  |
| `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml` | Add 4 env vars                                                   |
| n8n workflow (SRE alert dispatch)                                     | Split alerts, move fingerprint, per-job overrides                |

## Out of Scope

- Time-windowed batching at drain time (drain returns everything in buffer)
- Per-repo or per-alert-type batch config beyond per-job overrides
- Grafana dashboard creation (follow-up)
- Alert grouping/correlation beyond AlertManager's native grouping
