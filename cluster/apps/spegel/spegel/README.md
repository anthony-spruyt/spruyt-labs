# spegel Runbook

## Purpose and Scope

Spegel is a stateless cluster-local OCI registry mirror that runs on all nodes in a Kubernetes cluster, providing distributed caching of container images to reduce external registry bandwidth and improve pull times. This readme documents the GitOps layout, deployment workflow, and operations for maintaining Spegel in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                      | Description                                                                |
| --------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/spegel/README.md`                           | This runbook and component overview.                                       |
| `cluster/apps/spegel/kustomization.yaml`                  | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/spegel/namespace.yaml`                      | Namespace definition for the spegel workload.                              |
| `cluster/apps/spegel/spegel/ks.yaml`                      | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/spegel/spegel/app/kustomization.yaml`       | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/spegel/spegel/app/release.yaml`             | Flux `HelmRelease` referencing the upstream spegel chart.                  |
| `cluster/apps/spegel/spegel/app/values.yaml`              | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/flux/meta/repositories/helm/spegel-ocirepo.yaml` | OCI repository definition pinning the upstream Spegel source.              |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage container registry services.
- Ensure the workstation can reach the Kubernetes API and that the `spegel` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the Spegel Helm release to provide distributed container image caching across the Kubernetes cluster.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n spegel get helmrelease spegel -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/spegel/spegel/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr spegel --namespace spegel
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization spegel --with-source
   flux get kustomizations spegel -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease spegel -n spegel
   ```

#### Phase 3 – Monitor Registry Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n spegel -l app.kubernetes.io/name=spegel
   kubectl logs -n spegel daemonset/spegel
   ```

2. Check service endpoints:

   ```bash
   kubectl get svc -n spegel spegel
   ```

3. Monitor metrics (if enabled):

   ```bash
   kubectl get servicemonitor -n spegel
   ```

#### Phase 4 – Manual Registry Operations

1. Check mirror configuration in containerd.
2. Verify image pulls are using the mirror.
3. Monitor cache hit rates.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization spegel -n flux-system
   flux suspend helmrelease spegel -n spegel
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization spegel -n flux-system
   flux resume helmrelease spegel -n spegel
   ```

4. Scale daemonset to zero as a last resort:

   ```bash
   kubectl -n spegel scale ds/spegel --replicas=0
   ```

### Validation

- `kubectl get pods -n spegel` shows spegel pods running on all nodes.
- `kubectl get svc -n spegel` shows registry service available.
- `flux get helmrelease spegel -n spegel` reports `Ready=True` with no pending upgrades.
- Container image pulls succeed and utilize the mirror.

### Troubleshooting Guidance

- If image pulls fail, check mirror configuration and connectivity.
- For pod scheduling issues, verify node selectors and tolerations.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr spegel --namespace spegel
  kubeconform -strict -summary ./cluster/apps/spegel/spegel/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                     | Purpose                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                          | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                      | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr spegel --namespace spegel` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n spegel`             | Validates pod deployment across nodes.                                                           |
| `kubectl get svc -n spegel`              | Ensures registry service availability.                                                           |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Container registry operations: [cluster/apps/README.md](/cluster/apps/README.md)
- Spegel documentation: <https://github.com/spegel-org/spegel>
- Spegel Helm chart: <https://artifacthub.io/packages/helm/spegel/spegel>
