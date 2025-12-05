# rook-ceph-operator Runbook

## Overview

Rook Ceph Operator manages the lifecycle of Ceph storage clusters in Kubernetes, providing distributed block storage, shared filesystem storage, and object storage. This readme documents the GitOps layout, deployment workflow, and operations for maintaining the Rook Ceph operator in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                               | Description                                                                |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `cluster/apps/rook-ceph/rook-ceph-operator/README.md`              | This runbook and component overview.                                       |
| `cluster/apps/rook-ceph/kustomization.yaml`                        | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/rook-ceph/namespace.yaml`                            | Namespace definition for the rook-ceph workload.                           |
| `cluster/apps/rook-ceph/rook-ceph-operator/ks.yaml`                | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/rook-ceph/rook-ceph-operator/app/kustomization.yaml` | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/rook-ceph/rook-ceph-operator/app/release.yaml`       | Flux `HelmRelease` referencing the upstream rook-ceph operator chart.      |
| `cluster/apps/rook-ceph/rook-ceph-operator/app/values.yaml`        | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/flux/meta/repositories/helm/rook-ceph-ocirepo.yaml`       | OCI repository definition pinning the upstream Rook Ceph source.           |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage storage clusters.
- Ensure the workstation can reach the Kubernetes API and that the `rook-ceph-operator` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Storage nodes must be available for Ceph cluster deployment.

## Operation

### Summary

Operate the Rook Ceph operator Helm release to manage Ceph storage clusters, providing persistent storage for Kubernetes workloads.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when storage operations could impact availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n rook-ceph get helmrelease rook-ceph-operator -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/rook-ceph/rook-ceph-operator/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr rook-ceph-operator --namespace rook-ceph
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization rook-ceph-operator --with-source
   flux get kustomizations rook-ceph-operator -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease rook-ceph-operator -n rook-ceph
   ```

#### Phase 3 – Monitor Storage Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n rook-ceph -l app=rook-ceph-operator
   kubectl logs -n rook-ceph deployment/rook-ceph-operator
   ```

2. Check Ceph cluster status:

   ```bash
   kubectl get cephcluster -n rook-ceph
   kubectl ceph status
   ```

3. Monitor storage classes:

   ```bash
   kubectl get storageclass
   ```

#### Phase 4 – Manual Storage Operations

1. Check cluster health:

   ```bash
   kubectl ceph health
   ```

2. View OSD status:

   ```bash
   kubectl get cephosd -n rook-ceph
   ```

3. Monitor PVCs:

   ```bash
   kubectl get pvc -A
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization rook-ceph-operator -n flux-system
   flux suspend helmrelease rook-ceph-operator -n rook-ceph
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization rook-ceph-operator -n flux-system
   flux resume helmrelease rook-ceph-operator -n rook-ceph
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n rook-ceph scale deploy/rook-ceph-operator --replicas=0
   ```

### Validation

- `kubectl get pods -n rook-ceph` shows rook-ceph-operator pods in Running state.
- `kubectl get cephcluster -n rook-ceph` shows healthy Ceph clusters.
- `flux get helmrelease rook-ceph-operator -n rook-ceph` reports `Ready=True` with no pending upgrades.
- Storage classes are available and PVCs can be provisioned.

### Troubleshooting Guidance

- If storage provisioning fails, check Ceph cluster health and OSD status.
- For operator issues, inspect logs and CRD installations.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr rook-ceph-operator --namespace rook-ceph
  kubeconform -strict -summary ./cluster/apps/rook-ceph/rook-ceph-operator/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                    | Purpose                                                                                          |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                         | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                     | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr rook-ceph-operator --namespace rook-ceph` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n rook-ceph`                         | Validates pod deployment and readiness.                                                          |
| `kubectl ceph status`                                   | Ensures Ceph cluster health.                                                                     |

<!-- markdownlint-enable MD013 -->

## References

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Storage operations: [cluster/apps/README.md](/cluster/apps/README.md)
- Rook Ceph documentation: <https://rook.io/docs/rook/latest/>
- Rook Ceph Helm chart: <https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph-cluster>
