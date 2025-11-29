# snapshot-controller Runbook

## Purpose and Scope

The snapshot-controller implements the control loop for CSI snapshot functionality in Kubernetes. It manages VolumeSnapshot and VolumeSnapshotContent resources, enabling point-in-time snapshots of persistent volumes through CSI drivers. This controller is essential for backup and restore operations in the cluster.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the snapshot controller healthy.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                              | Description                                                                |
| --------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/kube-system/README.md`                                              | This runbook and component overview.                                       |
| `cluster/apps/kube-system/kustomization.yaml`                                     | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/kube-system/snapshot-controller/ks.yaml`                            | Flux `Kustomization` driving reconciliation of the controller manifests.   |
| `cluster/apps/kube-system/snapshot-controller/app/kustomization.yaml`             | Overlay combining RBAC and deployment resources.                           |
| `cluster/apps/kube-system/snapshot-controller/app/rbac-snapshot-controller.yaml`  | RBAC configuration for snapshot controller service account and roles.      |
| `cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml` | Deployment manifest for the snapshot controller.                           |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage storage snapshots.
- Ensure the workstation can reach the Kubernetes API and that the `snapshot-controller` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- CSI drivers supporting snapshots must be installed and configured.

## Operational Runbook

### Summary

Operate the snapshot-controller deployment to manage CSI volume snapshots, ensuring backup and restore capabilities for persistent storage.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when snapshot controller updates could impact backup operations.
- Capture the current deployment status for rollback reference:

  ```bash
  kubectl -n kube-system get deployment snapshot-controller -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update manifests under `cluster/apps/kube-system/snapshot-controller/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching manifests:

   ```bash
   flux diff ks snapshot-controller --path=./cluster/apps/kube-system/snapshot-controller
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization snapshot-controller --with-source
   flux get kustomizations snapshot-controller -n flux-system
   ```

2. Confirm the deployment is healthy:

   ```bash
   kubectl -n kube-system get deployment snapshot-controller
   ```

#### Phase 3 – Monitor Snapshot Operations

1. Watch snapshot controller pods:

   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=snapshot-controller
   ```

2. Check VolumeSnapshot resources:

   ```bash
   kubectl get volumesnapshots -A
   kubectl get volumesnapshotcontents
   ```

3. Validate snapshot classes:

   ```bash
   kubectl get volumesnapshotclasses
   ```

#### Phase 4 – Manual Intervention for Failed Snapshots

1. Inspect controller logs for snapshot failures:

   ```bash
   kubectl logs -n kube-system deployment/snapshot-controller
   ```

2. Check VolumeSnapshot status and events:

   ```bash
   kubectl describe volumesnapshot <name>
   kubectl get events -n <namespace> --field-selector involvedObject.kind=VolumeSnapshot
   ```

3. Restart the deployment if needed:

   ```bash
   kubectl rollout restart deployment/snapshot-controller -n kube-system
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization snapshot-controller -n flux-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization snapshot-controller -n flux-system
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n kube-system scale deployment/snapshot-controller --replicas=0
   ```

### Validation

- `kubectl get deployment snapshot-controller -n kube-system` shows desired replicas ready.
- `kubectl get volumesnapshotclasses` lists available snapshot classes.
- `flux get kustomizations snapshot-controller -n flux-system` reports `Ready=True`.
- Volume snapshots can be created and restored successfully.

### Troubleshooting Guidance

- If snapshots fail to create, check CSI driver logs and VolumeSnapshot status:

  ```bash
  kubectl describe volumesnapshot <name>
  kubectl logs -n <csi-namespace> <csi-controller-pod>
  ```

- For RBAC issues, verify the snapshot-controller service account permissions:

  ```bash
  kubectl auth can-i create volumesnapshots --as system:serviceaccount:kube-system:snapshot-controller
  ```

- When manifests fail to apply, check for schema compliance:

  ```bash
  kubeconform -strict -summary ./cluster/apps/kube-system/snapshot-controller/app
  ```

- If pods crash, capture logs and describe the pod:

  ```bash
  kubectl -n kube-system get pods
  kubectl -n kube-system describe pod <pod-name>
  ```

- For snapshot class issues, ensure CSI drivers support the required snapshot features.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                                                     | Purpose                                                                                          |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                                          | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                                                      | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff ks snapshot-controller --path=./cluster/apps/kube-system/snapshot-controller` | Previews Kustomize changes before reconciliation.                                                |
| `kubectl get volumesnapshotclasses`                                                      | Validates snapshot classes are available.                                                        |
| `kubectl get deployment snapshot-controller -n kube-system`                              | Confirms controller deployment health.                                                           |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Upstream snapshot controller documentation: <https://github.com/kubernetes-csi/external-snapshotter>
- Kubernetes CSI snapshot documentation: <https://kubernetes.io/docs/concepts/storage/volume-snapshots/>
- VolumeSnapshot API reference: <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#volumesnapshot-v1-snapshot-storage-k8s-io>
