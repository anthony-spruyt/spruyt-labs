# vaultwarden Runbook

## Purpose and Scope

Vaultwarden is a Bitwarden-compatible server written in Rust, providing secure password management and credential storage for individuals and teams. This readme documents the GitOps layout, deployment workflow, and operations for maintaining Vaultwarden in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                     | Description                                                                |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `cluster/apps/vaultwarden/README.md`                                     | This runbook and component overview.                                       |
| `cluster/apps/vaultwarden/kustomization.yaml`                            | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/vaultwarden/namespace.yaml`                                | Namespace definition for the vaultwarden workload.                         |
| `cluster/apps/vaultwarden/vaultwarden/ks.yaml`                           | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/vaultwarden/vaultwarden/app/kustomization.yaml`            | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/vaultwarden/vaultwarden/app/release.yaml`                  | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.          |
| `cluster/apps/vaultwarden/vaultwarden/app/values.yaml`                   | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/vaultwarden/vaultwarden/app/network-policies.yaml`         | Network policies for secure communication.                                 |
| `cluster/apps/vaultwarden/vaultwarden/app/persistent-volume-claims.yaml` | PVC for data persistence.                                                  |
| `cluster/flux/meta/repositories/helm/bjw-s-charts.yaml`                  | Helm repository definition pinning the upstream app-template source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage password management services.
- Ensure the workstation can reach the Kubernetes API and that the `vaultwarden` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Vaultwarden secrets must be available via external-secrets.

## Operational Runbook

### Summary

Operate the Vaultwarden Helm release to provide secure password management and credential storage.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n vaultwarden get helmrelease vaultwarden -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/vaultwarden/vaultwarden/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr vaultwarden --namespace vaultwarden
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization vaultwarden --with-source
   flux get kustomizations vaultwarden -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease vaultwarden -n vaultwarden
   ```

#### Phase 3 – Monitor Vaultwarden Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n vaultwarden -l app.kubernetes.io/name=vaultwarden
   kubectl logs -n vaultwarden deployment/vaultwarden
   ```

2. Check service endpoints:

   ```bash
   kubectl get svc -n vaultwarden vaultwarden
   ```

3. Access admin interface (if enabled).

#### Phase 4 – Manual Password Operations

1. Check database integrity.
2. Monitor user registrations and logins.
3. Verify backup procedures for encrypted data.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization vaultwarden -n flux-system
   flux suspend helmrelease vaultwarden -n vaultwarden
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization vaultwarden -n flux-system
   flux resume helmrelease vaultwarden -n vaultwarden
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n vaultwarden scale deploy/vaultwarden --replicas=0
   ```

### Validation

- `kubectl get pods -n vaultwarden` shows vaultwarden pods in Running state.
- `kubectl get svc -n vaultwarden` shows vaultwarden service available.
- `flux get helmrelease vaultwarden -n vaultwarden` reports `Ready=True` with no pending upgrades.
- Users can access the web interface and manage passwords.

### Troubleshooting Guidance

- If login fails, check admin token and user configurations.
- For database issues, verify PVC and data persistence.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr vaultwarden --namespace vaultwarden
  kubeconform -strict -summary ./cluster/apps/vaultwarden/vaultwarden/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                          | Purpose                                                                                          |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                               | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                           | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr vaultwarden --namespace vaultwarden`            | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n vaultwarden`                             | Validates pod deployment and readiness.                                                          |
| `curl http://vaultwarden.vaultwarden.svc.cluster.local/alive` | Tests service health.                                                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Security services: [cluster/apps/README.md](/cluster/apps/README.md)
- Vaultwarden documentation: <https://github.com/dani-garcia/vaultwarden>
- bjw-s app-template Helm chart: <https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common>
