# plugin-barman-cloud Runbook

## Purpose and Scope

The plugin-barman-cloud deployment provides a plugin for CloudNativePG to enable cloud-based backups for PostgreSQL clusters. This runbook documents the GitOps layout, deployment workflow, and operations required to keep the plugin healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                    | Description                                                                |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/cnpg-system/README.md`                                    | This runbook and component overview.                                       |
| `cluster/apps/cnpg-system/kustomization.yaml`                           | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/cnpg-system/namespace.yaml`                               | Namespace definition for the cnpg-system workload.                         |
| `cluster/apps/cnpg-system/plugin-barman-cloud/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/cnpg-system/plugin-barman-cloud/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/cnpg-system/plugin-barman-cloud/app/release.yaml`         | Flux `HelmRelease` referencing the plugin-barman-cloud chart.              |
| `cluster/apps/cnpg-system/plugin-barman-cloud/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/cnpg-system/plugin-barman-cloud/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/helm/cloudnative-pg.yaml`               | Helm repository definition pinning the upstream CloudNativePG source.      |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage PostgreSQL backups.
- Ensure the workstation can reach the Kubernetes API and that the `plugin-barman-cloud` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the plugin-barman-cloud Helm release to enable cloud backups for PostgreSQL clusters managed by CNPG.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when backup operations could impact performance.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n cnpg-system get helmrelease plugin-barman-cloud -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/cnpg-system/plugin-barman-cloud/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr plugin-barman-cloud --namespace cnpg-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization plugin-barman-cloud --with-source
   flux get kustomizations plugin-barman-cloud -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease plugin-barman-cloud -n cnpg-system
   ```

#### Phase 3 – Monitor Plugin Health

1. Watch plugin pods:

   ```bash
   kubectl get pods -n cnpg-system -l app.kubernetes.io/name=plugin-barman-cloud
   ```

2. Validate backup configurations in PostgreSQL clusters.
3. Ensure backups are running successfully.

#### Phase 4 – Manual Intervention for Backup Issues

1. Restart the deployment if backups fail:

   ```bash
   kubectl -n cnpg-system rollout restart deploy/plugin-barman-cloud
   ```

2. For cloud credentials issues, verify secrets are correct.
3. Inspect logs for backup errors:

   ```bash
   kubectl logs -n cnpg-system deploy/plugin-barman-cloud
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization plugin-barman-cloud -n flux-system
   flux suspend helmrelease plugin-barman-cloud -n cnpg-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization plugin-barman-cloud -n flux-system
   flux resume helmrelease plugin-barman-cloud -n cnpg-system
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n cnpg-system scale deploy/plugin-barman-cloud --replicas=0
   ```

### Validation

- `kubectl get pods -n cnpg-system` shows running pods with no restarts.
- `kubectl get helmrelease plugin-barman-cloud -n cnpg-system` reports `Ready=True` with no pending upgrades.
- PostgreSQL clusters can configure cloud backups.
- Backup jobs complete successfully.

### Troubleshooting Guidance

- If backups fail, check cloud credentials and permissions.
- For plugin not loading, ensure CNPG operator is running and plugin is installed.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr plugin-barman-cloud --namespace cnpg-system
  kubeconform -strict -summary ./cluster/apps/cnpg-system/plugin-barman-cloud/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n cnpg-system get pods
  kubectl -n cnpg-system describe pod <pod-name>
  ```

- For backup issues, consult CNPG and Barman documentation.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                                            | Purpose                                                                                          |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                                 | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                                             | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr plugin-barman-cloud --namespace cnpg-system`                      | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n cnpg-system get events --sort-by=.lastTimestamp`                    | Confirms the plugin starts after rollout.                                                        |
| `kubectl get pods -n cnpg-system -l app.kubernetes.io/name=plugin-barman-cloud` | Validates that the plugin is running.                                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../../cluster/flux/README.md)
- CNPG operations: [cluster/apps/cnpg-system/cnpg-operator/README.md](../cnpg-operator/README.md)
- Upstream plugin-barman-cloud documentation: <https://cloudnative-pg.io/docs/>
