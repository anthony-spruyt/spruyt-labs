# Agent Queue Worker - BullMQ Job Orchestration

## Overview

BullMQ-based job queue worker that coordinates agent job lifecycle. Receives job submissions via HTTP API, dispatches to n8n webhooks, and tracks completion via callbacks. Includes Bull Board dashboard for queue visibility.

> **Note**: HelmRelease resources are created in the target namespace specified by ks.yaml `targetNamespace`.

## Prerequisites

- Kubernetes cluster with Flux CD
- agent-valkey (Valkey instance for BullMQ queue storage)
- n8n (webhook target for job dispatch)

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n agent-worker-system -l app.kubernetes.io/instance=agent-queue-worker
flux get helmrelease -n agent-worker-system agent-queue-worker

# Force reconcile (GitOps approach)
flux reconcile kustomization agent-queue-worker --with-source

# View logs
kubectl logs -n agent-worker-system -l app.kubernetes.io/controller=worker

# Check worker health
kubectl exec -n agent-worker-system deploy/agent-queue-worker-worker -- wget -qO- http://localhost:3000/livez
kubectl exec -n agent-worker-system deploy/agent-queue-worker-worker -- wget -qO- http://localhost:3000/readyz
```

## Timeouts

### Per-Role Job Timeouts

Used for `Promise.race` deadline in processor, Valkey active lock TTL, and session token TTL.

| Role       | Timeout             | Use Case                    |
| ---------- | ------------------- | --------------------------- |
| `triage`   | 10min (600,000ms)   | Read-only PR/issue analysis |
| `fix`      | 30min (1,800,000ms) | Code changes                |
| `validate` | 30min (1,800,000ms) | Post-push validation        |
| `execute`  | 60min (3,600,000ms) | Full execution workflows    |
| fallback   | 30min (1,800,000ms) | Unknown roles               |

### BullMQ Worker Settings

| Setting            | Value                 | Purpose                                |
| ------------------ | --------------------- | -------------------------------------- |
| `stalledInterval`  | 60s                   | How often to check for stalled jobs    |
| `lockDuration`     | 120s                  | Job lock lifetime (2x stalledInterval) |
| `maxStalledCount`  | 1                     | Stall recoveries before failing        |
| `removeOnComplete` | 1h                    | Completed job retention                |
| `removeOnFail`     | 7d / 500 count        | Failed job retention                   |
| `attempts`         | 2                     | Max attempts per job                   |
| `backoff`          | exponential, 30s base | Retry delay strategy                   |

### Pod Deadline Enforcement

Kyverno enforces `activeDeadlineSeconds` on agent pods based on the `agent-timeout` annotation set at pod creation. See [Kyverno policies README](../../kyverno/policies/README.md#set-agent-deadline) for policy details.

## Troubleshooting

### Common Issues

1. **Worker not connecting to Valkey**

   - **Symptom**: Pod CrashLoopBackOff, logs show Redis connection errors
   - **Resolution**: Verify agent-valkey pod is running and CNP allows egress on port 6379

1. **Jobs stuck in queue**

   - **Symptom**: `agent_queue_depth` metric stays elevated, VMRule alert fires after 75m
   - **Resolution**: Check n8n webhook availability, verify CNP allows egress to n8n-system on port 5678

1. **Circuit breaker open**

   - **Symptom**: POST /jobs returns 429 with `circuit_open`
   - **Resolution**: POST /circuit/{repo}/reset to clear, investigate underlying failures

## References

- [BullMQ Documentation](https://docs.bullmq.io/)
- [bjw-s app-template](https://bjw-s.github.io/helm-charts/docs/app-template/)
