# Plan: Worker resilience — ioredis factory + lock renewal limit

## Context

Jobs stopped being processed due to two compounding issues:

1. BullMQ Worker/Queue use a plain `{ host, port, password }` connection object — no auto-reconnect when Valkey drops
2. Lock renewal failures in processor.ts are logged but ignored — the worker thread spins forever on a dead job, blocking all other work

## Changes

### 1. Pass ioredis instance to BullMQ (ts/agent-queue-worker/src/index.ts)

Current (lines 22-26):

```typescript
const connection = {
  host: config.VALKEY_HOST,
  port: config.VALKEY_PORT,
  password: config.VALKEY_PASSWORD,
};
```

Replace with: pass the existing `redis` ioredis client (lines 14-20, already configured with `retryStrategy` and `maxRetriesPerRequest: null`) as the `connection` for both Queue and Worker.

BullMQ will:

- Use the ioredis instance directly (auto-reconnect via retryStrategy)
- Call `.duplicate()` for the Worker's blocking connection

Delete the standalone `connection` object entirely.

### 2. Lock renewal failure limit (ts/agent-queue-worker/src/processor.ts)

In the lock extender setInterval (lines 118-133):

- Add a `lockRenewalFailures` counter per job
- After 3 consecutive failures, cancel the job callback and throw a `DelayedError` so the job gets retried instead of spinning forever
- Reset counter on successful renewal

No new error class needed — `DelayedError` already exists and is handled specially by the `failed` handler (line 172 of lifecycle.ts skips circuit breaker trip for it).

### 3. Tests

**processor.test.ts** — add test:

- `lock renewal fails 3 times in a row → throws DelayedError`
- Verify callback is resolved with `cancelled` and lock extender is cleared
- Verify `agent:active` cleanup happens

## Files to modify

- `ts/agent-queue-worker/src/index.ts` — use ioredis instance for BullMQ connections
- `ts/agent-queue-worker/src/processor.ts` — track lock renewal failures, abort after threshold
- `ts/agent-queue-worker/src/processor.test.ts` — new test for lock failure limit

## Verification

- `npx vitest run` — all existing + new tests pass
- Build: `npx tsc --noEmit`
- Deploy via Flux (commit + push)
