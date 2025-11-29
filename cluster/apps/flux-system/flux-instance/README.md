# flux-instance Runbook

## Purpose and Scope

The flux-instance deployment provides the Flux GitOps operator instance for managing the cluster's continuous deployment. This runbook documents the GitOps layout, deployment workflow, and operations required to keep the Flux instance healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/flux-system/flux-instance/README.md`                | This runbook and component overview.                                       |
| `cluster/apps/flux-system/kustomization.yaml`                     | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/flux-system/namespace.yaml`                         | Namespace definition for the flux-system workload.                         |
| `cluster/apps/flux-system/flux-instance/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/flux-system/flux-instance/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/flux-system/flux-instance/app/release.yaml`         | Flux `HelmRelease` referencing the flux-instance chart.                    |
| `cluster/apps/flux-system/flux-instance/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/flux-system/flux-instance/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/helm/controlplaneio-fluxcd.yaml`  | Helm repository definition pinning the upstream flux-instance source.      |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage Flux instances.
- Ensure the workstation can reach the Kubernetes API and that the `flux-instance` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the flux-instance Helm release to manage the Flux GitOps controllers and reconciliation.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when GitOps changes could impact deployments.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n flux-system get helmrelease flux-instance -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/flux-system/flux-instance/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr flux-instance --namespace flux-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization flux-instance --with-source
   flux get kustomizations flux-instance -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease flux-instance -n flux-system
   ```

#### Phase 3 – Monitor Flux Controllers

1. Watch Flux pods and CRDs:

   ```bash
   kubectl get pods -n flux-system
   kubectl get crd | grep flux
   ```

2. Validate GitRepository and Kustomization reconciliation.
3. Ensure deployments are updated.

#### Phase 4 – Manual Intervention for Reconciliation Issues

1. Restart the deployment if reconciliation fails:

   ```bash
   kubectl -n flux-system rollout restart deploy/flux-instance
   ```

2. For Git access issues, verify secrets are correct.
3. Inspect logs for reconciliation errors:

   ```bash
   kubectl logs -n flux-system deploy/flux-instance
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization flux-instance -n flux-system
   flux suspend helmrelease flux-instance -n flux-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization flux-instance -n flux-system
   flux resume helmrelease flux-instance -n flux-system
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n flux-system scale deploy/flux-instance --replicas=0
   ```

### Validation

- `kubectl get pods -n flux-system` shows running pods with no restarts.
- `kubectl get helmrelease flux-instance -n flux-system` reports `Ready=True` with no pending upgrades.
- CRDs are installed and GitOps reconciliation works.
- Applications are deployed via Flux.

### Troubleshooting Guidance

- If reconciliation fails, check Git access and repository status.
- For CRD issues, ensure the operator is running and has permissions.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr flux-instance --namespace flux-system
  kubeconform -strict -summary ./cluster/apps/flux-system/flux-instance/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n flux-system get pods
  kubectl -n flux-system describe pod <pod-name>
  ```

- For Flux issues, consult Flux documentation.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                         | Purpose                                                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| `task validate`                                              | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                          | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr flux-instance --namespace flux-system`         | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n flux-system get events --sort-by=.lastTimestamp` | Confirms the operator starts reconciling after rollout.                                          |
| `kubectl get crd                                             | grep flux`                                                                                       | Validates that CRDs are installed. |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-operator/README.md](../flux-operator/README.md)
- Certificate management: [cluster/apps/README.md](../../README.md)
- Upstream flux-instance documentation: <https://fluxcd.control-plane.io/operator/>
