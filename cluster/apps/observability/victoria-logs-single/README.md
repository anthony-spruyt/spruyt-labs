# victoria-logs-single Runbook

## Purpose and Scope

Victoria Logs Single is a high-performance, cost-effective log management system designed for storing and querying large volumes of logs. This readme documents the GitOps layout, deployment workflow, and operations for maintaining Victoria Logs in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                     | Description                                                                |
| ------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `cluster/apps/observability/victoria-logs-single/README.md`              | This runbook and component overview.                                       |
| `cluster/apps/observability/kustomization.yaml`                          | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/observability/namespace.yaml`                              | Namespace definition for the observability workload.                       |
| `cluster/apps/observability/victoria-logs-single/ks.yaml`                | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/observability/victoria-logs-single/app/kustomization.yaml` | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/observability/victoria-logs-single/app/release.yaml`       | Flux `HelmRelease` referencing the upstream victoria-logs-single chart.    |
| `cluster/apps/observability/victoria-logs-single/app/values.yaml`        | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/flux/meta/repositories/helm/victoria-logs-single-ocirepo.yaml`  | OCI repository definition pinning the upstream Victoria Logs source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage logging infrastructure.
- Ensure the workstation can reach the Kubernetes API and that the `victoria-logs-single` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Storage must be available for log persistence.

## Operational Runbook

### Summary

Operate the Victoria Logs Single Helm release to provide centralized log storage and querying capabilities.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n observability get helmrelease victoria-logs-single -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/observability/victoria-logs-single/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr victoria-logs-single --namespace observability
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization victoria-logs-single --with-source
   flux get kustomizations victoria-logs-single -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease victoria-logs-single -n observability
   ```

#### Phase 3 – Monitor Log Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=victoria-logs-single
   kubectl logs -n observability statefulset/victoria-logs-single-server
   ```

2. Check service endpoints:

   ```bash
   kubectl get svc -n observability victoria-logs-single-server
   ```

3. Monitor Vector log collection:

   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/name=vector
   kubectl logs -n observability daemonset/vector
   ```

#### Phase 4 – Manual Log Operations

1. Query logs via HTTP API:

   ```bash
   curl "http://victoria-logs-single-server.observability.svc:9428/select/logsql/query?query=_time:>now-1h"
   ```

2. Check log ingestion metrics.
3. Verify retention policies.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization victoria-logs-single -n flux-system
   flux suspend helmrelease victoria-logs-single -n observability
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization victoria-logs-single -n flux-system
   flux resume helmrelease victoria-logs-single -n observability
   ```

4. Scale statefulset to zero as a last resort:

   ```bash
   kubectl -n observability scale sts/victoria-logs-single-server --replicas=0
   ```

### Validation

- `kubectl get pods -n observability` shows victoria-logs-single and vector pods in Running state.
- `kubectl get svc -n observability` shows log services available.
- `flux get helmrelease victoria-logs-single -n observability` reports `Ready=True` with no pending upgrades.
- Logs are being ingested and can be queried.

### Troubleshooting Guidance

- If log ingestion fails, check Vector configuration and connectivity.
- For storage issues, verify PVC and retention settings.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr victoria-logs-single --namespace observability
  kubeconform -strict -summary ./cluster/apps/observability/victoria-logs-single/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                          | Purpose                                                                                          |
| ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                               | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                           | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr victoria-logs-single --namespace observability` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n observability`                           | Validates pod deployment and readiness.                                                          |
| `curl` to query endpoint                                      | Tests log querying functionality.                                                                |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- Observability: [cluster/apps/README.md](/cluster/apps/README.md)
- Victoria Logs documentation: <https://docs.victoriametrics.com/VictoriaLogs/>
- Victoria Logs Helm chart: <https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-logs-single>
