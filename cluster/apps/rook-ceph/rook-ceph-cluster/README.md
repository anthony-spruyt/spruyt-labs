# rook-ceph-cluster Runbook

## Purpose and Scope

Rook Ceph Cluster deploys and manages a Ceph storage cluster using Rook, providing distributed block storage, shared filesystem storage, and object storage for Kubernetes workloads. This readme documents the GitOps layout, deployment workflow, and operations for maintaining the Ceph cluster in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                 | Description                                                                |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/rook-ceph/rook-ceph-cluster/README.md`                 | This runbook and component overview.                                       |
| `cluster/apps/rook-ceph/kustomization.yaml`                          | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/rook-ceph/namespace.yaml`                              | Namespace definition for the rook-ceph workload.                           |
| `cluster/apps/rook-ceph/rook-ceph-cluster/ks.yaml`                   | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/rook-ceph/rook-ceph-cluster/app/kustomization.yaml`    | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml`          | Flux `HelmRelease` referencing the upstream rook-ceph-cluster chart.       |
| `cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml`           | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/rook-ceph/rook-ceph-cluster/app/config-maps.yaml`      | Additional ConfigMaps for cluster configuration.                           |
| `cluster/apps/rook-ceph/rook-ceph-cluster/storage/`                  | Storage class and PVC configurations.                                      |
| `cluster/flux/meta/repositories/helm/rook-ceph-cluster-ocirepo.yaml` | OCI repository definition pinning the upstream Rook Ceph cluster source.   |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage storage clusters.
- Ensure the workstation can reach the Kubernetes API and that the `rook-ceph-cluster` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Storage devices must be available and properly configured for Ceph OSDs.

## Operational Runbook

### Summary

Operate the Rook Ceph cluster Helm release to deploy and manage a Ceph storage cluster for persistent storage in Kubernetes.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when storage operations could impact availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n rook-ceph get helmrelease rook-ceph-cluster -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/rook-ceph/rook-ceph-cluster/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr rook-ceph-cluster --namespace rook-ceph
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization rook-ceph-cluster --with-source
   flux get kustomizations rook-ceph-cluster -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease rook-ceph-cluster -n rook-ceph
   ```

#### Phase 3 – Monitor Cluster Health

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n rook-ceph -l app=rook-ceph-mon
   kubectl logs -n rook-ceph deployment/rook-ceph-mgr
   ```

2. Check Ceph cluster status:

   ```bash
   kubectl get cephcluster -n rook-ceph
   kubectl ceph status
   ```

3. Monitor OSD status:

   ```bash
   kubectl get cephosd -n rook-ceph
   ```

#### Phase 4 – Manual Cluster Operations

1. Check cluster health:

   ```bash
   kubectl ceph health
   ```

2. View cluster details:

   ```bash
   kubectl ceph cluster status
   ```

3. Access toolbox for debugging:

   ```bash
   kubectl -n rook-ceph exec -it deployment/rook-ceph-tools -- bash
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization rook-ceph-cluster -n flux-system
   flux suspend helmrelease rook-ceph-cluster -n rook-ceph
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization rook-ceph-cluster -n flux-system
   flux resume helmrelease rook-ceph-cluster -n rook-ceph
   ```

4. Scale deployments to zero as a last resort (not recommended for storage):

   ```bash
   kubectl -n rook-ceph scale deploy/rook-ceph-mgr --replicas=0
   ```

### Validation

- `kubectl get cephcluster -n rook-ceph` shows healthy Ceph clusters.
- `kubectl ceph health` reports HEALTH_OK or HEALTH_WARN.
- `kubectl get storageclass` shows Ceph storage classes available.
- `flux get helmrelease rook-ceph-cluster -n rook-ceph` reports `Ready=True` with no pending upgrades.

### Troubleshooting Guidance

- If cluster health is degraded, check OSD and MON status.
- For storage provisioning issues, verify device availability and configuration.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr rook-ceph-cluster --namespace rook-ceph
  kubeconform -strict -summary ./cluster/apps/rook-ceph/rook-ceph-cluster/app
  ```

- Use the toolbox pod for advanced debugging.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                   | Purpose                                                                                          |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `task validate`                                        | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                    | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr rook-ceph-cluster --namespace rook-ceph` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get cephcluster -n rook-ceph`                 | Validates Ceph cluster deployment.                                                               |
| `kubectl ceph status`                                  | Ensures cluster health.                                                                          |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Storage operations: [cluster/apps/README.md](/cluster/apps/README.md)
- Rook Ceph documentation: <https://rook.io/docs/rook/latest/>
- Rook Ceph cluster Helm chart: <https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph-cluster>
