# whoami Runbook

## Purpose and Scope

Whoami is a simple web service that returns information about HTTP requests, commonly used for testing ingress controllers, load balancers, and network connectivity. This readme documents the GitOps layout, deployment workflow, and operations for maintaining the whoami service in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                    | Description                                                                |
| ------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/whoami/README.md`                         | This runbook and component overview.                                       |
| `cluster/apps/whoami/kustomization.yaml`                | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/whoami/namespace.yaml`                    | Namespace definition for the whoami workload.                              |
| `cluster/apps/whoami/whoami/ks.yaml`                    | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/whoami/whoami/app/kustomization.yaml`     | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/whoami/whoami/app/release.yaml`           | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.          |
| `cluster/apps/whoami/whoami/app/values.yaml`            | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/flux/meta/repositories/helm/bjw-s-charts.yaml` | Helm repository definition pinning the upstream app-template source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage network testing services.
- Ensure the workstation can reach the Kubernetes API and that the `whoami` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the whoami Helm release to provide a simple HTTP service for testing and debugging network configurations.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n whoami get helmrelease whoami -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/whoami/whoami/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr whoami --namespace whoami
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization whoami --with-source
   flux get kustomizations whoami -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease whoami -n whoami
   ```

#### Phase 3 – Monitor Service

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n whoami -l app.kubernetes.io/name=whoami
   kubectl logs -n whoami deployment/whoami
   ```

2. Test the service:

   ```bash
   curl http://whoami.whoami.svc.cluster.local
   ```

3. Check service endpoints:

   ```bash
   kubectl get svc -n whoami whoami
   ```

#### Phase 4 – Manual Intervention

1. Check HTTP response codes and content.
2. Verify network policies and ingress rules if applicable.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization whoami -n flux-system
   flux suspend helmrelease whoami -n whoami
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization whoami -n flux-system
   flux resume helmrelease whoami -n whoami
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n whoami scale deploy/whoami --replicas=0
   ```

### Validation

- `kubectl get pods -n whoami` shows whoami pods in Running state.
- `kubectl get svc -n whoami` shows service with endpoints.
- `flux get helmrelease whoami -n whoami` reports `Ready=True` with no pending upgrades.
- HTTP requests return expected response with request details.

### Troubleshooting Guidance

- If HTTP requests fail, check pod logs and service configuration.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr whoami --namespace whoami
  kubeconform -strict -summary ./cluster/apps/whoami/whoami/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                     | Purpose                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                          | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                      | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr whoami --namespace whoami` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n whoami`             | Validates pod deployment and readiness.                                                          |
| `curl` to service endpoint               | Ensures HTTP service functionality.                                                              |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../../cluster/flux/README.md)
- Network testing: [cluster/apps/README.md](../../README.md)
- Traefik whoami documentation: <https://github.com/traefik/whoami>
- bjw-s app-template Helm chart: <https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common>
