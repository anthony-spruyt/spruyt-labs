# Agent Queue Worker - BullMQ Job Orchestration

## Overview

Queues agent jobs (Renovate triage/fix, validate, execute-issue, SRE) in front of n8n, so bursts are serialised, deduplicated and circuit-broken per repo instead of spawning agent pods directly. n8n submits jobs over HTTP, the worker dispatches each to the n8n `agent-dispatch` webhook and waits for n8n's callback. Bull Board runs as a second controller behind Authentik forward-auth. Source is in
`ts/agent-queue-worker/`; `agent-valkey` is its dedicated BullMQ store.

## Operations

### Shared secret wiring

`agent-queue-worker-secrets` holds two bearer secrets: `WORKER_TO_N8N_SECRET` (worker → n8n dispatch webhook) and `N8N_TO_WORKER_SECRET` (n8n → worker API, also used by Bull Board). The separate `agent-queue-worker-n8n-secret` Kustomization (`n8n-secret/`) copies both into `n8n-system` as `agent-worker-auth` through an ESO SecretStore that reads back into `agent-worker-system` (RBAC in
`app/secret-reader-rbac.yaml`). Rotate by editing the SOPS file here only; ESO propagates to n8n within 5 minutes.

### Timeouts

The timeout for each role is `timeoutMs` in `ts/agent-queue-worker/src/roles/*.ts` (registered in `roles/registry.ts`). One value drives four things, which is why they must not be tuned separately:

- the `Promise.race` deadline in the processor
- the TTL of the Valkey `agent:active:<job>` lock and `agent:session:<job>` token
- `timeout_seconds` sent to n8n, which the Claude Code node writes to the pod's `agent-timeout` annotation
- via that annotation, the pod's `activeDeadlineSeconds`, set by Kyverno `set-agent-deadline` (default 3h if the annotation is missing)

The `AgentQueueStuck` alert in `app/vmrule.yaml` fires after 75m, sized as "max role timeout + buffer". The longest role timeout is now 3h (`execute-issue`), so a single long job can trip it while the queue is healthy. Revisit the alert when changing role timeouts.

BullMQ worker settings are in `src/index.ts` (`lockDuration`/`stalledInterval` 120s, `maxStalledCount` 2) and job defaults in `src/queue/options.ts` (`attempts: 1`; n8n owns retries). A 30s lock extender keeps long jobs from being marked stalled.

### Health gate

Before dispatching, the worker checks n8n and LiteLLM health. If either is down it pauses the worker (not the queue) and polls at `HEALTH_POLL_INTERVAL_MS` until both recover, with no upper bound. The lock extender starts before the health check, so the waiting job keeps its lock. Pauses are counted in `agent_health_pause_total`. `agent_queue_paused` reflects only a queue-level pause, so a
health-gate pause does **not** suppress `AgentQueueStuck`; a long n8n or LiteLLM outage fires it.

### Circuit breaker

Five failed jobs for the same repo within an hour open that repo's circuit: `POST /jobs` returns `429 {"reason":"circuit_open"}` until the failures age out. Reset early with `POST /circuit/<owner%2Frepo>/reset` using the `N8N_TO_WORKER_SECRET` bearer token, after fixing the underlying failure.

## Troubleshooting

1. **Repeated `could not renew lock for job <id>` every 30s for one job**

   - **Cause**: The job key is corrupted in Valkey (`WRONGTYPE`). Happens when `job.moveToDelayed()` runs while BullMQ's internal lock timer is still armed. The health-gate path no longer does this, but the `cancelled` path in `processor.ts` still calls `moveToDelayed`.
   - **Fix**: Delete the job in Bull Board (or Valkey), then restart the worker pod.

2. **Jobs queue but never dispatch, no errors**

   - **Cause**: The health gate has paused the worker because n8n or LiteLLM health is failing, or their CNPs no longer allow the worker's health probes.
   - **Fix**: Check `agent_health_pause_total` and the worker logs for `Dependencies unhealthy`, then the `allow-n8n-health-egress` / `allow-litellm-health-egress` CNPs and the matching ingress on each side.

3. **Dispatch fails with 401 from n8n**

   - **Cause**: `agent-worker-auth` in `n8n-system` is out of sync with `agent-queue-worker-secrets`.
   - **Fix**: Check the `agent-worker-auth` ExternalSecret in `n8n-system` is `SecretSynced`.

## References

- [BullMQ Documentation](https://docs.bullmq.io/)
