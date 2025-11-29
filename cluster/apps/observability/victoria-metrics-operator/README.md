# victoria-metrics-operator Runbook

## Purpose and Scope

The victoria-metrics-operator controller deploys the Victoria Metrics operator, which manages Victoria Metrics monitoring components like VMCluster, VMSingle, VMAlert, and VMAgent through Kubernetes custom resources.

It provides CRDs, admission webhooks for validation, and automated lifecycle management for the Victoria Metrics ecosystem in the spruyt-labs environment. This readme documents the GitOps layout, deployment workflow, and operations required to keep the operator healthy.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                            | Description                                                                |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/observability/victoria-metrics-operator/README.md`                | Parent runbook and component overview.                                     |
| `cluster/apps/observability/kustomization.yaml`                                 | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/observability/namespace.yaml`                                     | Namespace definition for the observability workload.                       |
| `cluster/apps/observability/victoria-metrics-operator/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/observability/victoria-metrics-operator/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/observability/victoria-metrics-operator/app/release.yaml`         | Flux `HelmRelease` referencing the Victoria Metrics operator chart.        |
| `cluster/apps/observability/victoria-metrics-operator/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/observability/victoria-metrics-operator/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/victoria-metrics-operator-ocirepo.yaml`         | Helm repository definition pinning the upstream Victoria Metrics source.   |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage CRDs and admission webhooks.
- Ensure the workstation can reach the Kubernetes API and that the `victoria-metrics-operator` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Verify that cert-manager is operational for webhook certificates.

## Operational Runbook

### Summary

Operate the victoria-metrics-operator Helm release to provide Kubernetes-native management of Victoria Metrics monitoring resources with validation and automation.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when CRD changes could impact monitoring.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n observability get helmrelease victoria-metrics-operator -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/observability/victoria-metrics-operator/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr victoria-metrics-operator --namespace observability
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization victoria-metrics-operator --with-source
   flux get kustomizations victoria-metrics-operator -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease victoria-metrics-operator -n observability
   ```

#### Phase 3 – Monitor Operator Operations

1. Watch operator logs for CRD reconciliation and webhook events:

   ```bash
   kubectl logs -n observability deploy/victoria-metrics-operator
   ```

2. Validate CRD installation:

   ```bash
   kubectl get crd | grep victoriametrics
   ```

3. Check admission webhook configuration:

   ```bash
   kubectl get validatingwebhookconfigurations | grep victoria
   ```

#### Phase 4 – Manual Intervention for Issues

1. Restart the operator deployment if reconciliation stalls:

   ```bash
   kubectl rollout restart deploy/victoria-metrics-operator -n observability
   ```

2. Inspect webhook certificates for expiration:

   ```bash
   kubectl describe secret victoria-metrics-operator-validation -n observability
   ```

3. Verify cert-manager integration if webhooks fail.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization victoria-metrics-operator -n flux-system
   flux suspend helmrelease victoria-metrics-operator -n observability
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization victoria-metrics-operator -n flux-system
   flux resume helmrelease victoria-metrics-operator -n observability
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n observability scale deploy/victoria-metrics-operator --replicas=0
   ```

### Validation

- `kubectl get pods -n observability` shows victoria-metrics-operator pod running and ready.
- `kubectl get crd` lists Victoria Metrics CRDs (vmcluster, vmsingle, etc.).
- `flux get helmrelease victoria-metrics-operator -n observability` reports `Ready=True` with no pending upgrades.
- Admission webhooks validate Victoria Metrics resources correctly.
- Operator reconciles custom resources without errors.

### Troubleshooting Guidance

- If CRDs fail to install, check operator logs for permission issues.
- For webhook validation failures, inspect certificate status and cert-manager.
- When operator pod crashes, check resource limits and cluster capacity.
- If reconciliation loops, review custom resource specifications for errors.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                               | Purpose                                                              |
| ------------------------------------------------------------------ | -------------------------------------------------------------------- | ------------------------------------------------ |
| `task validate`                                                    | Runs repository schema validation (kubeconform, yamllint, conftest). |
| `task dev-env:lint`                                                | Executes markdownlint, prettier, and ancillary linters.              |
| `flux diff hr victoria-metrics-operator --namespace observability` | Previews rendered Helm changes before reconciliation.                |
| `kubectl -n observability get events --sort-by=.lastTimestamp`     | Confirms operator startup and CRD installation events.               |
| `kubectl get crd                                                   | grep victoriametrics`                                                | Validates CRD availability for custom resources. |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Cert-manager operations: [cluster/apps/cert-manager/cert-manager/README.md](../../../../cluster/apps/cert-manager/cert-manager/README.md)
- Victoria Metrics k8s stack: [cluster/apps/observability/victoria-metrics-k8s-stack/README.md](../victoria-metrics-k8s-stack/README.md)
- Upstream Victoria Metrics operator: <https://docs.victoriametrics.com/operator/>
- Kubernetes admission webhooks: <https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/>
