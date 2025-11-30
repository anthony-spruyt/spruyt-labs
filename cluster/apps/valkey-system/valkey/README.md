# valkey Runbook

## Purpose and Scope

Valkey is a high-performance data structure store that is fully compatible with Redis, providing in-memory key-value storage for caching, session management, and message queuing. This readme documents the GitOps layout, deployment workflow, and operations for maintaining Valkey in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                        | Description                                                                |
| ----------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/valkey-system/valkey/README.md`               | This runbook and component overview.                                       |
| `cluster/apps/valkey-system/kustomization.yaml`             | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/valkey-system/namespace.yaml`                 | Namespace definition for the valkey-system workload.                       |
| `cluster/apps/valkey-system/valkey/ks.yaml`                 | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/valkey-system/valkey/app/kustomization.yaml`  | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/valkey-system/valkey/app/release.yaml`        | Flux `HelmRelease` referencing the upstream valkey-io/valkey chart.        |
| `cluster/apps/valkey-system/valkey/app/values.yaml`         | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/flux/meta/repositories/helm/valkey-io-charts.yaml` | Helm repository definition pinning the upstream Valkey source.             |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage data storage services.
- Ensure the workstation can reach the Kubernetes API and that the `valkey` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Valkey secrets must be available via external-secrets.

## Operational Runbook

### Summary

Operate the Valkey Helm release to provide Redis-compatible data storage for applications.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n valkey-system get helmrelease valkey -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/valkey-system/valkey/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr valkey --namespace valkey-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization valkey --with-source
   flux get kustomizations valkey -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease valkey -n valkey-system
   ```

#### Phase 3 – Monitor Valkey Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n valkey-system -l app.kubernetes.io/name=valkey
   kubectl logs -n valkey-system statefulset/valkey
   ```

2. Check service endpoints:

   ```bash
   kubectl get svc -n valkey-system valkey
   ```

3. Connect to Valkey:

   ```bash
   kubectl exec -it -n valkey-system statefulset/valkey -- valkey-cli
   ```

#### Phase 4 – Manual Database Operations

1. Check Valkey info:

   ```bash
   kubectl exec -it -n valkey-system statefulset/valkey -- valkey-cli info
   ```

2. Monitor connections and performance.
3. Verify ACL configurations.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization valkey -n flux-system
   flux suspend helmrelease valkey -n valkey-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization valkey -n flux-system
   flux resume helmrelease valkey -n valkey-system
   ```

4. Scale statefulset to zero as a last resort:

   ```bash
   kubectl -n valkey-system scale sts/valkey --replicas=0
   ```

### Validation

- `kubectl get pods -n valkey-system` shows valkey pods in Running state.
- `kubectl get svc -n valkey-system` shows valkey service available.
- `flux get helmrelease valkey -n valkey-system` reports `Ready=True` with no pending upgrades.
- Applications can connect and perform operations on Valkey.

### Troubleshooting Guidance

- If connections fail, check authentication and ACL settings.
- For performance issues, monitor memory usage and connections.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr valkey --namespace valkey-system
  kubeconform -strict -summary ./cluster/apps/valkey-system/valkey/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                | Purpose                                                                                          |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                     | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                 | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr valkey --namespace valkey-system`     | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n valkey-system`                 | Validates pod deployment and readiness.                                                          |
| `kubectl exec -it statefulset/valkey -- valkey-cli` | Tests Valkey connectivity.                                                                       |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Data storage: [cluster/apps/README.md](/cluster/apps/README.md)
- Valkey documentation: <https://valkey.io/>
- Valkey Helm chart: <https://github.com/valkey-io/valkey-helm>
