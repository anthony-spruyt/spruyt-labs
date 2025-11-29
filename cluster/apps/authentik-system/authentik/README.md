# authentik Runbook

## Purpose and Scope

Authentik is an open-source IAM solution providing authentication, authorization, and user management with SSO, MFA, and policy-based access control. This readme documents the GitOps layout, deployment workflow, and operations for maintaining authentik in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                                | Description                                                                        |
| ----------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `cluster/apps/authentik-system/README.md`                                           | This runbook and component overview.                                               |
| `cluster/apps/authentik-system/kustomization.yaml`                                  | Top-level Kustomize entry that namespaces resources and delegates to Flux.         |
| `cluster/apps/authentik-system/namespace.yaml`                                      | Namespace definition for the authentik-system workload.                            |
| `cluster/apps/authentik-system/authentik/ks.yaml`                                   | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.            |
| `cluster/apps/authentik-system/authentik/app/kustomization.yaml`                    | Overlay combining the HelmRelease, CNPG resources, and generated values ConfigMap. |
| `cluster/apps/authentik-system/authentik/app/release.yaml`                          | Flux `HelmRelease` referencing the upstream goauthentik chart.                     |
| `cluster/apps/authentik-system/authentik/app/values.yaml`                           | Rendered values supplied to the chart via ConfigMap.                               |
| `cluster/apps/authentik-system/authentik/app/authentik-cnpg-cluster.yaml`           | CNPG PostgreSQL cluster configuration for authentik database.                      |
| `cluster/apps/authentik-system/authentik/app/authentik-cnpg-object-stores.yaml`     | Barman cloud object store configuration for backups.                               |
| `cluster/apps/authentik-system/authentik/app/authentik-cnpg-poolers.yaml`           | CNPG pooler configuration (commented out, for future scaling).                     |
| `cluster/apps/authentik-system/authentik/app/authentik-cnpg-scheduled-backups.yaml` | Scheduled backup configuration for PostgreSQL cluster.                             |
| `cluster/apps/authentik-system/authentik/app/persistent-volume-claim.yaml`          | PVC for authentik application storage.                                             |
| `cluster/apps/authentik-system/authentik/app/kustomizeconfig.yaml`                  | Remaps ConfigMap keys to Helm values for deterministic patches.                    |
| `cluster/apps/authentik-system/authentik/app/authentik-secrets.sops.yaml`           | Encrypted secrets for authentik and backup credentials.                            |
| `cluster/flux/meta/repositories/helm/goauthentik-charts.yaml`                       | Helm repository definition pinning the upstream authentik source.                  |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage authentik configurations.
- Ensure the workstation can reach the Kubernetes API and that the `authentik` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Verify dependencies are healthy: CNPG operator, barman-cloud plugin, and rook-ceph storage.

## Operational Runbook

### Summary

Operate the authentik Helm release alongside a CNPG-managed PostgreSQL cluster to provide centralized identity and access management services, including user authentication, authorization policies, and integrations with external providers.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when authentik downtime could impact user access.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n authentik-system get helmrelease authentik -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/authentik-system/authentik/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr authentik --namespace authentik-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization authentik --with-source
   flux get kustomizations authentik -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease authentik -n authentik-system
   ```

#### Phase 3 – Monitor Deployment and Database

1. Watch authentik and PostgreSQL pods during rollout:

   ```bash
   kubectl get pods -n authentik-system
   kubectl get clusters.postgresql.cnpg.io -n authentik-system
   ```

2. Validate events emitted by the deployments:

   ```bash
   kubectl get events -n authentik-system --sort-by=.lastTimestamp
   ```

3. Ensure authentik web UI is accessible and database connections are established.

#### Phase 4 – Manual Intervention for Issues

1. Restart pods if authentication fails:

   ```bash
   kubectl rollout restart deployment/authentik -n authentik-system
   ```

2. Check database connectivity and logs:

   ```bash
   kubectl logs -n authentik-system deployment/authentik
   kubectl logs -n authentik-system cluster/authentik-cnpg-cluster-1
   ```

3. For backup issues, inspect scheduled backup status:

   ```bash
   kubectl get scheduledbackups.postgresql.cnpg.io -n authentik-system
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization authentik -n flux-system
   flux suspend helmrelease authentik -n authentik-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization authentik -n flux-system
   flux resume helmrelease authentik -n authentik-system
   ```

4. Scale authentik deployment to zero as a last resort:

   ```bash
   kubectl -n authentik-system scale deploy/authentik --replicas=0
   ```

### Validation

- `kubectl get pods -n authentik-system` shows authentik and PostgreSQL pods in Running state.
- `kubectl get clusters.postgresql.cnpg.io -n authentik-system` reports the CNPG cluster as Ready.
- `flux get helmrelease authentik -n authentik-system` reports `Ready=True` with no pending upgrades.
- Authentik web UI is accessible and users can authenticate successfully.
- Scheduled backups complete without errors (`kubectl get backups.postgresql.cnpg.io -n authentik-system`).

### Troubleshooting Guidance

- If pods fail to start, inspect logs for configuration or secret issues:

  ```bash
  kubectl -n authentik-system describe pod <pod-name>
  kubectl -n authentik-system logs <pod-name>
  ```

- For database connection errors, verify CNPG cluster status and secrets:

  ```bash
  kubectl get secrets -n authentik-system
  kubectl describe cluster authentik-cnpg-cluster -n authentik-system
  ```

- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr authentik --namespace authentik-system
  kubeconform -strict -summary ./cluster/apps/authentik-system/authentik/app
  ```

- If backups fail, check object store credentials and S3 access:

  ```bash
  kubectl logs -n authentik-system job/<backup-job-name>
  ```

- For authentication issues, consult authentik logs and configuration.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                              | Purpose                                                                                          |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                   | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                               | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr authentik --namespace authentik-system`             | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n authentik-system get events --sort-by=.lastTimestamp` | Confirms deployments emit healthy events after rollout.                                          |
| `kubectl get pods -n authentik-system`                            | Validates authentik and database pods are running.                                               |
| `kubectl get clusters.postgresql.cnpg.io -n authentik-system`     | Ensures CNPG cluster is operational.                                                             |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [../../../flux/README.md](../../../flux/README.md)
- CNPG operations: [../../cnpg-system/cnpg-operator/README.md](../../cnpg-system/cnpg-operator/README.md)
- External secrets management: [../../external-secrets/external-secrets/README.md](../../external-secrets/external-secrets/README.md)
- Rook Ceph storage: [../../rook-ceph/rook-ceph-operator/README.md](../../rook-ceph/rook-ceph-operator/README.md)
- Upstream authentik documentation: <https://docs.goauthentik.io/>
- Authentik Helm chart: <https://github.com/goauthentik/helm>
- CNPG documentation: <https://cloudnative-pg.io/docs/>

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of Authentik deployment tasks, focusing on Helm release status, database connectivity, and authentication validation.

### Authentik Deployment Status Workflow

```bash
If flux get helmrelease authentik -n authentik-system --no-headers | grep -v "True" > /dev/null
Then:
  Run flux reconcile helmrelease authentik -n authentik-system
  Expected output: Reconciliation completes without errors
  If reconciliation fails:
    Run kubectl logs -n authentik-system deployment/authentik --previous
    Expected output: Error logs indicating failure reason
    Recovery: Check values.yaml for configuration issues; verify secrets decryption
  Else:
    Run flux get helmrelease authentik -n authentik-system
    Expected output: Status shows Ready=True
    Proceed to database health check
Else:
  Proceed to database health check
```

### Database Connectivity Workflow

```bash
If kubectl get clusters.postgresql.cnpg.io authentik-cnpg-cluster -n authentik-system --no-headers | grep -v "Ready" > /dev/null
Then:
  Run kubectl describe cluster authentik-cnpg-cluster -n authentik-system
  Expected output: Cluster status and events
  If cluster not ready:
    Run kubectl logs -n authentik-system cluster/authentik-cnpg-cluster-1
    Expected output: PostgreSQL startup logs
    Recovery: Check PVC status with kubectl get pvc -n authentik-system; verify CNPG operator health
  Else:
    Run kubectl exec -n authentik-system cluster/authentik-cnpg-cluster-1 -- psql -U authentik -d authentik -c "SELECT 1"
    Expected output: Query succeeds
    Proceed to authentication validation
Else:
  Proceed to authentication validation
```

### Authentication Validation Workflow

```bash
If kubectl get pods -n authentik-system -l app.kubernetes.io/name=authentik --no-headers | grep -v "Running" > /dev/null
Then:
  Run kubectl describe pod -n authentik-system -l app.kubernetes.io/name=authentik
  Expected output: Pod events and status
  If pod not running:
    Run kubectl logs -n authentik-system deployment/authentik
    Expected output: Application logs
    Recovery: Verify database connection string; check for migration errors
  Else:
    Run curl -k https://authentik.internal/-/health/ready/
    Expected output: HTTP 200 OK
    If health check fails:
      Run kubectl logs -n authentik-system deployment/authentik | grep ERROR
      Expected output: Specific error messages
      Recovery: Restart deployment with kubectl rollout restart deployment/authentik -n authentik-system
Else:
  Authentik deployment verified successfully
```
