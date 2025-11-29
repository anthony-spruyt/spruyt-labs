# flux-operator Runbook

## Purpose and Scope

The flux-operator controller manages Flux installations in the Kubernetes cluster, enabling declarative management of GitOps deployments. It provides a way to install, upgrade, and manage Flux controllers and their configurations through Kubernetes resources.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the flux-operator healthy.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/flux-system/flux-operator/README.md`                | This runbook and component overview.                                       |
| `cluster/apps/flux-system/kustomization.yaml`                     | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/flux-system/namespace.yaml`                         | Namespace definition for the flux-system workload.                         |
| `cluster/apps/flux-system/flux-operator/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/flux-system/flux-operator/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/flux-system/flux-operator/app/release.yaml`         | Flux `HelmRelease` referencing the flux-operator OCIRepository.            |
| `cluster/apps/flux-system/flux-operator/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/flux-system/flux-operator/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/flux-operator-ocirepo.yaml`       | OCIRepository definition pinning the upstream flux-operator source.        |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage Flux installations.
- Ensure the workstation can reach the Kubernetes API and that the `flux-operator` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the flux-operator Helm release to manage Flux installations declaratively, ensuring GitOps workflows remain functional and up-to-date.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when flux-operator updates could impact GitOps reconciliation.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n flux-system get helmrelease flux-operator -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/flux-system/flux-operator/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr flux-operator --namespace flux-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization flux-operator --with-source
   flux get kustomizations flux-operator -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease flux-operator -n flux-system
   ```

#### Phase 3 – Monitor Flux Instances

1. Watch for flux-operator managed Flux instances:

   ```bash
   kubectl get fluxinstances -A
   kubectl describe fluxinstance <name>
   ```

2. Validate events emitted by the operator:

   ```bash
   kubectl get events -n flux-system --sort-by=.lastTimestamp
   ```

3. Ensure Flux controllers remain healthy after updates (`flux check`).

#### Phase 4 – Manual Intervention for Stuck Reconciling

1. Check flux-operator logs for reconciliation failures:

   ```bash
   kubectl logs -n flux-system deploy/flux-operator
   ```

2. Inspect FluxInstance status for errors:

   ```bash
   kubectl get fluxinstances -A -o wide
   kubectl describe fluxinstance <name>
   ```

3. Restart the operator if needed:

   ```bash
   kubectl rollout restart deploy/flux-operator -n flux-system
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization flux-operator -n flux-system
   flux suspend helmrelease flux-operator -n flux-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization flux-operator -n flux-system
   flux resume helmrelease flux-operator -n flux-system
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n flux-system scale deploy/flux-operator --replicas=0
   ```

### Validation

- `kubectl get fluxinstances -A` shows managed Flux instances in Ready state.
- `flux check` reports all controllers healthy with current versions.
- `flux get helmrelease flux-operator -n flux-system` reports `Ready=True` with no pending upgrades.
- Audit logs confirm the operator manages Flux installations without manual intervention.

### Troubleshooting Guidance

- If Flux instances fail to reconcile, inspect operator logs for policy violations and verify RBAC:

  ```bash
  kubectl auth can-i create fluxinstances --as system:serviceaccount:flux-system:flux-operator
  ```

- For repeated reconciliation failures, ensure OCIRepository is accessible and chart versions are valid.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr flux-operator --namespace flux-system
  kubeconform -strict -summary ./cluster/apps/flux-system/flux-operator/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n flux-system get pods
  kubectl -n flux-system describe pod <pod-name>
  ```

- For Flux instance creation issues, consult the flux-operator documentation for supported configurations.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                         | Purpose                                                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `task validate`                                              | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                          | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr flux-operator --namespace flux-system`         | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n flux-system get events --sort-by=.lastTimestamp` | Confirms the operator emits reconciliation events after rollout.                                 |
| `flux check`                                                 | Validates that managed Flux instances remain operational.                                        |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../flux-instance/README.md)
- OCIRepository management: [cluster/flux/meta/repositories/README.md](../../../flux/meta/repositories/README.md)
- Upstream flux-operator documentation: <https://github.com/controlplaneio-fluxcd/charts/tree/main/charts/flux-operator>
- Flux documentation: <https://fluxcd.io/>
