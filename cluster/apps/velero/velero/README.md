# velero Runbook

## Purpose and Scope

Velero is a Kubernetes backup/restore tool that provides disaster recovery, data migration, and data protection capabilities. This readme documents the GitOps layout, deployment workflow, and operations for maintaining Velero in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                | Description                                                                                                  |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `cluster/apps/velero/README.md`                     | This runbook and component overview.                                                                         |
| `cluster/apps/velero/kustomization.yaml`            | Top-level Kustomize entry that namespaces resources and delegates to Flux.                                   |
| `cluster/apps/velero/namespace.yaml`                | Namespace definition for the velero workload.                                                                |
| `cluster/apps/velero/velero/ks.yaml`                | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.                                      |
| `cluster/apps/velero/velero/app/kustomization.yaml` | Overlay combining the HelmRelease and generated values ConfigMap.                                            |
| `cluster/apps/velero/velero/app/release.yaml`       | Flux `HelmRelease` referencing the upstream vmware-tanzu/velero chart.                                       |
| `cluster/apps/velero/velero/app/values.yaml`        | Rendered values supplied to the chart via ConfigMap.                                                         |
| `cluster/apps/velero/velero/resources/`             | Supplemental resources reconciled alongside the HelmRelease (BackupStorageLocation, VolumeSnapshotLocation). |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage backup/restore operations.
- Ensure the workstation can reach the Kubernetes API and that the `velero` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- AWS credentials and S3 bucket must be configured for backup storage.

## Operational Runbook

### Summary

Operate the Velero Helm release to provide Kubernetes cluster backup and restore capabilities using AWS S3 and CSI snapshots.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when backup operations could impact performance.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n velero get helmrelease velero -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/velero/velero/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr velero --namespace velero
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization velero --with-source
   flux get kustomizations velero -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease velero -n velero
   ```

#### Phase 3 – Monitor Backup Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n velero -l app.kubernetes.io/name=velero
   kubectl logs -n velero deployment/velero
   ```

2. Check backup storage locations:

   ```bash
   velero backup-location get
   ```

3. Monitor backup jobs:

   ```bash
   velero backup get
   ```

#### Phase 4 – Manual Backup/Restore Operations

1. Create backups:

   ```bash
   velero backup create <backup-name> --include-namespaces <namespace>
   ```

2. Restore from backup:

   ```bash
   velero restore create --from-backup <backup-name>
   ```

3. Verify restore status:

   ```bash
   velero restore get
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization velero -n flux-system
   flux suspend helmrelease velero -n velero
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization velero -n flux-system
   flux resume helmrelease velero -n velero
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n velero scale deploy/velero --replicas=0
   ```

### Validation

- `kubectl get pods -n velero` shows velero pods in Running state.
- `velero backup-location get` shows available backup storage locations.
- `flux get helmrelease velero -n velero` reports `Ready=True` with no pending upgrades.
- Backup and restore operations complete successfully.

### Troubleshooting Guidance

- If backups fail, check AWS credentials and S3 bucket access.
- For restore issues, verify namespace and resource conflicts.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr velero --namespace velero
  kubeconform -strict -summary ./cluster/apps/velero/velero/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                     | Purpose                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                          | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                      | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr velero --namespace velero` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n velero`             | Validates pod deployment and readiness.                                                          |
| `velero backup-location get`             | Ensures backup storage configuration.                                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Backup operations: [cluster/apps/README.md](/cluster/apps/README.md)
- Velero documentation: <https://velero.io/docs/>
- VMware Tanzu Velero Helm chart: <https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero>
