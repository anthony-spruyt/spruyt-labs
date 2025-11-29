# n8n Runbook

## Purpose and Scope

The n8n controller deploys the n8n workflow automation platform for creating and managing automated workflows. It includes PostgreSQL database storage via CloudNativePG, Redis queue for job processing, and supports webhooks and task runners. This readme documents the GitOps layout, deployment workflow, and operations required to keep the n8n platform healthy in the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/n8n-system/README.md`                               | Parent runbook and component overview.                                     |
| `cluster/apps/n8n-system/kustomization.yaml`                      | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/n8n-system/namespace.yaml`                          | Namespace definition for the n8n workload.                                 |
| `cluster/apps/n8n-system/n8n/ks.yaml`                             | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/n8n-system/n8n/app/kustomization.yaml`              | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/n8n-system/n8n/app/release.yaml`                    | Flux `HelmRelease` referencing the n8n chart.                              |
| `cluster/apps/n8n-system/n8n/app/values.yaml`                     | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/n8n-system/n8n/app/kustomizeconfig.yaml`            | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/apps/n8n-system/n8n/app/n8n-cnpg-cluster.yaml`           | CNPG cluster definition for PostgreSQL.                                    |
| `cluster/apps/n8n-system/n8n/app/n8n-cnpg-object-stores.yaml`     | Object store configuration for backups.                                    |
| `cluster/apps/n8n-system/n8n/app/n8n-cnpg-poolers.yaml`           | Connection poolers for database.                                           |
| `cluster/apps/n8n-system/n8n/app/n8n-cnpg-scheduled-backups.yaml` | Scheduled backup jobs.                                                     |
| `cluster/apps/n8n-system/n8n/app/persistent-volume-claim.yaml`    | PVC for additional storage if needed.                                      |
| `cluster/flux/meta/repositories/n8n-ocirepo.yaml`                 | Helm repository definition pinning the upstream n8n source.                |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage n8n configurations and database secrets.
- Ensure the workstation can reach the Kubernetes API and that the `n8n` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Verify that required dependencies (CNPG operator, Valkey, Rook Ceph) are operational.

## Operational Runbook

### Summary

Operate the n8n Helm release to provide a scalable workflow automation platform with database persistence, queue processing, and webhook handling.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when workflow downtime could impact automation processes.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n n8n-system get helmrelease n8n -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/n8n-system/n8n/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr n8n --namespace n8n-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization n8n --with-source
   flux get kustomizations n8n -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease n8n -n n8n-system
   ```

#### Phase 3 – Monitor Platform Operations

1. Watch pod logs for workflow executions and errors:

   ```bash
   kubectl logs -n n8n-system deploy/n8n-main -f
   kubectl logs -n n8n-system deploy/n8n-worker -f
   ```

2. Validate database connectivity and CNPG cluster health:

   ```bash
   kubectl get cnpg -n n8n-system
   kubectl describe cnpg n8n-cnpg-cluster -n n8n-system
   ```

3. Check Redis queue status via Valkey:

   ```bash
   kubectl exec -n valkey-system deploy/valkey -- redis-cli ping
   ```

#### Phase 4 – Manual Intervention for Issues

1. Restart deployments if workflow executions stall:

   ```bash
   kubectl rollout restart deploy/n8n-main -n n8n-system
   kubectl rollout restart deploy/n8n-worker -n n8n-system
   ```

2. Inspect secrets for encryption keys and database credentials:

   ```bash
   kubectl describe secret n8n-secrets -n n8n-system
   kubectl describe secret n8n-cnpg-cluster-app -n n8n-system
   ```

3. For database issues, check CNPG logs and backups.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization n8n -n flux-system
   flux suspend helmrelease n8n -n n8n-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization n8n -n flux-system
   flux resume helmrelease n8n -n n8n-system
   ```

4. Consider scaling deployments to zero as a last resort:

   ```bash
   kubectl -n n8n-system scale deploy/n8n-main --replicas=0
   kubectl -n n8n-system scale deploy/n8n-worker --replicas=0
   ```

### Validation

- `kubectl get pods -n n8n-system` shows n8n-main, n8n-worker, n8n-webhook pods running and ready.
- `kubectl get cnpg -n n8n-system` reports n8n-cnpg-cluster as ready.
- `flux get helmrelease n8n -n n8n-system` reports `Ready=True` with no pending upgrades.
- Web UI accessible at <https://n8n.${EXTERNAL_DOMAIN}> with valid login.
- Workflows execute successfully with queue processing.

### Troubleshooting Guidance

- If pods fail to start, check database connection and secret references in logs.
- For workflow execution failures, inspect worker logs and Redis connectivity.
- When webhooks fail, verify ingress and TLS configuration.
- If database issues occur, review CNPG cluster status and backup schedules.
- For high resource usage, monitor workflow complexity and task runner configuration.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                        | Purpose                                                              |
| ----------------------------------------------------------- | -------------------------------------------------------------------- |
| `task validate`                                             | Runs repository schema validation (kubeconform, yamllint, conftest). |
| `task dev-env:lint`                                         | Executes markdownlint, prettier, and ancillary linters.              |
| `flux diff hr n8n --namespace n8n-system`                   | Previews rendered Helm changes before reconciliation.                |
| `kubectl -n n8n-system get events --sort-by=.lastTimestamp` | Confirms deployment events and health checks.                        |
| `kubectl get cnpg -n n8n-system`                            | Validates PostgreSQL cluster readiness.                              |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- CNPG operations: [cluster/apps/cnpg-system/cnpg-operator/README.md](/cluster/apps/cnpg-system/cnpg-operator/README.md)
- Valkey operations: [cluster/apps/valkey-system/valkey/README.md](/cluster/apps/valkey-system/valkey/README.md)
- Rook Ceph storage: [cluster/apps/rook-ceph/rook-ceph-cluster/README.md](/cluster/apps/rook-ceph/rook-ceph-cluster/README.md)
- Upstream n8n documentation: <https://docs.n8n.io/>
- n8n Helm chart: <https://github.com/8gears/n8n-helm-chart>
