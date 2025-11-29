# reloader Runbook

## Purpose and Scope

Reloader is a Kubernetes controller that watches for changes in ConfigMaps and Secrets and triggers rolling updates on deployments, daemonsets, and statefulsets that reference them. This readme documents the GitOps layout, deployment workflow, and operations for maintaining Reloader in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                       | Description                                                                |
| ---------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/reloader/README.md`                          | This runbook and component overview.                                       |
| `cluster/apps/reloader/kustomization.yaml`                 | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/reloader/namespace.yaml`                     | Namespace definition for the reloader workload.                            |
| `cluster/apps/reloader/reloader/ks.yaml`                   | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/reloader/reloader/app/kustomization.yaml`    | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/reloader/reloader/app/release.yaml`          | Flux `HelmRelease` referencing the upstream stakater/reloader chart.       |
| `cluster/apps/reloader/reloader/app/values.yaml`           | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/flux/meta/repositories/helm/stakater-charts.yaml` | Helm repository definition pinning the upstream Reloader source.           |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage configuration reloading services.
- Ensure the workstation can reach the Kubernetes API and that the `reloader` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the Reloader Helm release to automatically trigger rolling updates when ConfigMaps and Secrets change.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n reloader get helmrelease reloader -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/reloader/reloader/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr reloader --namespace reloader
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization reloader --with-source
   flux get kustomizations reloader -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease reloader -n reloader
   ```

#### Phase 3 – Monitor Reloader Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n reloader -l app.kubernetes.io/name=reloader
   kubectl logs -n reloader deployment/reloader
   ```

2. Check for reload annotations on workloads:

   ```bash
   kubectl get deployments -A -o yaml | grep -A5 "reloader.stakater.com"
   ```

3. Monitor reload events:

   ```bash
   kubectl get events -n reloader --field-selector reason=Reload
   ```

#### Phase 4 – Manual Reload Operations

1. Manually trigger reloads by updating ConfigMaps/Secrets.
2. Check which workloads are configured for auto-reload.
3. Verify rolling update behavior.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization reloader -n flux-system
   flux suspend helmrelease reloader -n reloader
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization reloader -n flux-system
   flux resume helmrelease reloader -n reloader
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n reloader scale deploy/reloader --replicas=0
   ```

### Validation

- `kubectl get pods -n reloader` shows reloader pods in Running state.
- `kubectl get deployments -A` shows workloads with reloader annotations.
- `flux get helmrelease reloader -n reloader` reports `Ready=True` with no pending upgrades.
- ConfigMap/Secret changes trigger rolling updates.

### Troubleshooting Guidance

- If reloads don't trigger, check annotation syntax and controller logs.
- For permission issues, verify RBAC rules.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr reloader --namespace reloader
  kubeconform -strict -summary ./cluster/apps/reloader/reloader/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                         | Purpose                                                                                          |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                              | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                          | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr reloader --namespace reloader` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n reloader`               | Validates pod deployment and readiness.                                                          |
| `kubectl get events -n reloader`             | Monitors reload events.                                                                          |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Configuration management: [cluster/apps/README.md](/cluster/apps/README.md)
- Reloader documentation: <https://github.com/stakater/Reloader>
- Stakater Reloader Helm chart: <https://github.com/stakater/Reloader/tree/master/deployments/kubernetes/chart/reloader>
