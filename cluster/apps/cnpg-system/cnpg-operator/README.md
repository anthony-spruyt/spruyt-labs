# cnpg-operator Runbook

## Purpose and Scope

The cnpg-operator (CloudNativePG) deployment provides a Kubernetes operator for managing PostgreSQL clusters. This runbook documents the GitOps layout, deployment workflow, and operations required to keep the operator healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/cnpg-system/README.md`                              | This runbook and component overview.                                       |
| `cluster/apps/cnpg-system/kustomization.yaml`                     | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/cnpg-system/namespace.yaml`                         | Namespace definition for the cnpg-system workload.                         |
| `cluster/apps/cnpg-system/cnpg-operator/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/cnpg-system/cnpg-operator/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/cnpg-system/cnpg-operator/app/release.yaml`         | Flux `HelmRelease` referencing the CloudNativePG chart.                    |
| `cluster/apps/cnpg-system/cnpg-operator/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/cnpg-system/cnpg-operator/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/helm/cloudnative-pg.yaml`         | Helm repository definition pinning the upstream CloudNativePG source.      |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage PostgreSQL clusters.
- Ensure the workstation can reach the Kubernetes API and that the `cnpg-operator` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the cnpg-operator Helm release to manage PostgreSQL clusters in the cluster, ensuring high availability and automated operations.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when operator downtime could impact database availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n cnpg-system get helmrelease cnpg-operator -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/cnpg-system/cnpg-operator/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr cnpg-operator --namespace cnpg-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization cnpg-operator --with-source
   flux get kustomizations cnpg-operator -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease cnpg-operator -n cnpg-system
   ```

#### Phase 3 – Monitor Operator Health

1. Watch operator pods and CRDs:

   ```bash
   kubectl get pods -n cnpg-system
   kubectl get crd | grep postgresql
   ```

2. Validate cluster creation and management.
3. Ensure PostgreSQL clusters are healthy.

#### Phase 4 – Manual Intervention for Operator Issues

1. Restart the deployment if reconciliation fails:

   ```bash
   kubectl -n cnpg-system rollout restart deploy/cnpg-operator
   ```

2. For CRD issues, check if the operator is running and has permissions.
3. Inspect logs for reconciliation errors:

   ```bash
   kubectl logs -n cnpg-system deploy/cnpg-operator
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization cnpg-operator -n flux-system
   flux suspend helmrelease cnpg-operator -n cnpg-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization cnpg-operator -n flux-system
   flux resume helmrelease cnpg-operator -n cnpg-system
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n cnpg-system scale deploy/cnpg-operator --replicas=0
   ```

### Validation

- `kubectl get pods -n cnpg-system` shows running pods with no restarts.
- `kubectl get helmrelease cnpg-operator -n cnpg-system` reports `Ready=True` with no pending upgrades.
- CRDs are installed and PostgreSQL clusters can be created.
- Database clusters are operational.

### Troubleshooting Guidance

- If operator fails to reconcile, check logs for RBAC or resource issues.
- For cluster creation failures, ensure storage and networking are available.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr cnpg-operator --namespace cnpg-system
  kubeconform -strict -summary ./cluster/apps/cnpg-system/cnpg-operator/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n cnpg-system get pods
  kubectl -n cnpg-system describe pod <pod-name>
  ```

- For PostgreSQL issues, consult CNPG documentation.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                         | Purpose                                                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| `task validate`                                              | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                          | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr cnpg-operator --namespace cnpg-system`         | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n cnpg-system get events --sort-by=.lastTimestamp` | Confirms the operator starts reconciling after rollout.                                          |
| `kubectl get crd                                             | grep postgresql`                                                                                 | Validates that CRDs are installed. |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../flux/README.md)
- CNPG operations: [cluster/apps/cnpg-system/cnpg-operator/README.md](../../cnpg-system/cnpg-operator/README.md)
- Upstream CNPG documentation: <https://cloudnative-pg.io/>
