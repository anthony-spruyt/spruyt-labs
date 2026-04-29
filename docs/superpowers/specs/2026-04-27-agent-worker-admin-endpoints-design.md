# Agent Worker Admin/Ops Endpoints

**Issue:** [#1098](https://github.com/anthony-spruyt/spruyt-labs/issues/1098) **Date:** 2026-04-27

## Problem

During E2E testing, stuck jobs, stale idempotency keys, and open circuit breakers required manual Redis access or waiting for TTL expiry. No operational tooling exists to manage these states.

## Solution

Add admin endpoints to `agent-queue-worker` for operational recovery. Serve admin UI through Bull Board's Express app (already has Traefik ingress + Authentik SSO). Enable Bull Board read-write mode for standard BullMQ job operations (retry, remove, clean).

## Architecture

```text
Browser → Traefik → Authentik → Bull Board (port 3001)
                                  ├── / (Bull Board UI — read-write)
                                  └── /admin (Admin UI — static HTML)
                                       └── /admin/api/* → proxy → Worker (port 3000)
                                                                    └── /admin/* endpoints
```

Two auth layers:

- **Human access:** Authentik SSO via Traefik forward auth (Bull Board ingress)
- **Admin API:** `ADMIN_SECRET` bearer token (worker-side, used by bull-board proxy)

## Admin Endpoints (on worker, port 3000)

All require `Authorization: Bearer <ADMIN_SECRET>`.

Admin routes match in `Router.handle()` before the existing `authenticate()` check (which uses `N8N_TO_WORKER_SECRET`). A separate `authenticateAdmin()` method validates `ADMIN_SECRET`. This keeps n8n and admin auth fully isolated.

### GET /admin/status

Returns circuit breaker states and orphaned Redis keys.

Response:

```json
{
  "circuits": {
    "owner/repo": { "recent_failures": 3, "open": true, "threshold": 5 }
  },
  "orphaned_keys": {
    "active": ["agent:active:job1"],
    "sessions": 1
  }
}
```

Implementation:

- SCAN `agent:circuit:*` keys, ZCOUNT each for failures in last hour, compare against threshold (5)
- SCAN `agent:active:*` keys, cross-check against BullMQ active jobs to find orphans
- SCAN `agent:session:*` keys, count total

### POST /admin/circuit/:repo/reset

Reset circuit breaker for a repo. Deletes `agent:circuit:<repo>` sorted set.

Response: `{ "reset": true }`

Note: existing `/circuit/:repo/reset` (n8n auth) stays for backwards compat.

### POST /admin/jobs/:jobId/purge

Remove BullMQ job and all associated Redis keys.

Keys deleted:

- `agent:active:<jobId>`
- `agent:completed:<jobId>`
- `agent:session:<jobId>:*` (SCAN + delete)
- `agent:result:<jobId>:*` (SCAN + delete)

Also removes BullMQ job via `queue.remove(jobId)`.

Response: `{ "purged": true, "keys_deleted": 6 }`

### POST /admin/jobs/:jobId/force-retry

Reset job data to force re-dispatch, then retry:

1. `job.updateData({ ...job.data, dispatch_state: "pending", dispatched_at: undefined })` — clears stale dispatch state so processor re-dispatches to n8n instead of polling for a dead callback
1. `job.retry()` — moves job from `failed` back to `waiting`
1. Delete application-level Redis keys (`agent:active:*`, `agent:completed:*`, `agent:session:*`, `agent:result:*`)

Does NOT call `queue.remove()` — the job must remain in BullMQ for retry to work.

Fails if job doesn't exist or isn't in failed state.

Response: `{ "retried": true }`

### POST /admin/redis/flush-prefix/:prefix

Delete all Redis keys matching `<prefix>:*`.

Allowlisted prefixes only:

- `agent:circuit`
- `agent:completed`
- `agent:session`
- `agent:result`
- `agent:rate`
- `agent:revert-depth`

`agent:active` is excluded — these are NX locks for in-flight jobs. Bulk deletion risks duplicate dispatch. Individual cleanup via `/admin/jobs/:jobId/purge` instead. Orphaned locks expire via TTL.

Returns 400 for non-allowlisted prefixes.

Response: `{ "flushed": true, "keys_deleted": 12 }`

## Bull Board Changes

### Read-Write Mode

`READ_ONLY` already flipped to `"false"` in `values.yaml` (done manually). Enables built-in BullMQ actions:

- Retry failed jobs
- Remove jobs
- Clean completed/failed

### Admin UI Page

Add `/admin` route to Bull Board Express app serving static HTML with:

- **Status panel** — displays circuit states, orphaned keys (auto-refreshes)
- **Circuit reset** — dropdown of repos with open circuits, reset button
- **Job purge** — text input for jobId, purge button
- **Force retry** — text input for jobId, retry button
- **Flush prefix** — dropdown of allowed prefixes, flush button with confirmation

### Admin API Proxy

Add `/admin/api/*` routes to Bull Board Express app that proxy to worker:

- Strip `/admin/api` prefix, forward to `http://agent-queue-worker-worker.agent-worker-system.svc:3000/admin/*`
- Attach `Authorization: Bearer <ADMIN_SECRET>` header
- Forward response back to client

## Config Changes

### New env var: ADMIN_SECRET

Add to `ConfigSchema` in `config.ts`:

```typescript
ADMIN_SECRET: z.string().min(1),
```

### SOPS secret

Add `ADMIN_SECRET` to `agent-queue-worker-secrets.sops.yaml`.

### values.yaml changes

Worker container — `ADMIN_SECRET` injected via existing `secretRef` (already covers all keys in SOPS secret).

Bull Board container — add `ADMIN_SECRET` env var:

```yaml
ADMIN_SECRET:
  valueFrom:
    secretKeyRef:
      name: agent-queue-worker-secrets
      key: ADMIN_SECRET
```

`READ_ONLY` already `"false"` (done manually).

## Network Policy Changes

Two new CNPs required for bull-board → worker admin API proxy:

**1. Egress from bull-board to worker:**

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-bull-board-worker-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
      app.kubernetes.io/controller: bull-board
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: agent-worker-system
            k8s:app.kubernetes.io/instance: agent-queue-worker
            k8s:app.kubernetes.io/name: agent-queue-worker
            k8s:app.kubernetes.io/controller: worker
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
```

**2. Ingress on worker from bull-board** (required because worker already has ingress CNPs, so Cilium default-denies unlisted sources):

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-bull-board-admin-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
      app.kubernetes.io/controller: worker
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: agent-worker-system
            k8s:app.kubernetes.io/instance: agent-queue-worker
            k8s:app.kubernetes.io/name: agent-queue-worker
            k8s:app.kubernetes.io/controller: bull-board
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
```

## File Changes Summary

### TypeScript source (`ts/agent-queue-worker/`)

| File                      | Change                                                                                                                                                                                               |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/config.ts`           | Add `ADMIN_SECRET` to schema                                                                                                                                                                         |
| `src/routes.ts`           | Add admin route handlers with separate `authenticateAdmin()` check. Admin routes (`/admin/*`) match before the existing `authenticate()` call and use `ADMIN_SECRET`. Existing n8n routes unchanged. |
| `bull-board/src/index.ts` | Add admin UI page, proxy routes, `ADMIN_SECRET` config                                                                                                                                               |

### Kubernetes manifests (`cluster/apps/agent-worker-system/agent-queue-worker/`)

| File                                       | Change                                                                 |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| `app/values.yaml`                          | Add `ADMIN_SECRET` to bull-board env (`READ_ONLY` already flipped)     |
| `app/network-policies.yaml`                | Add bull-board → worker egress CNP and worker ← bull-board ingress CNP |
| `app/agent-queue-worker-secrets.sops.yaml` | Add `ADMIN_SECRET` key (user does manually)                            |

### Container images

Both `agent-queue-worker` and `bull-board` images need rebuild + tag bump after code changes.

## Out of Scope

- Admin endpoint rate limiting (low traffic, behind SSO)
- Audit logging for admin actions (logger.info calls sufficient)
- RBAC/role-based admin permissions (single admin token sufficient)
