# victoria-metrics-k8s-stack Runbook

## Purpose and Scope

The victoria-metrics-k8s-stack controller deploys a comprehensive monitoring stack using Victoria Metrics components, including VMSingle for metrics storage, VMAgent for collection, VMAlert for alerting, Alertmanager for alert handling, Grafana for visualization, and exporters for node and Kubernetes metrics.

It also configures scraping for etcd, kube-scheduler, and kube-controller-manager. This readme documents the GitOps layout, deployment workflow, and operations required to keep the monitoring stack healthy in the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                             | Description                                                                |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/observability/victoria-metrics-k8s-stack/README.md`                | Parent runbook and component overview.                                     |
| `cluster/apps/observability/kustomization.yaml`                                  | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/observability/namespace.yaml`                                      | Namespace definition for the observability workload.                       |
| `cluster/apps/observability/victoria-metrics-k8s-stack/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/release.yaml`         | Flux `HelmRelease` referencing the Victoria Metrics k8s stack chart.       |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/victoria-metrics-k8s-stack-ocirepo.yaml`         | Helm repository definition pinning the upstream Victoria Metrics source.   |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage monitoring resources and secrets.
- Ensure the workstation can reach the Kubernetes API and that the `victoria-metrics-k8s-stack` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Verify that Victoria Metrics operator and etcd secrets are available.

## Operational Runbook

### Summary

Operate the victoria-metrics-k8s-stack Helm release to provide end-to-end monitoring with metrics collection, storage, alerting, and visualization for the Kubernetes cluster.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when monitoring downtime could impact observability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n observability get helmrelease victoria-metrics-k8s-stack -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/observability/victoria-metrics-k8s-stack/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr victoria-metrics-k8s-stack --namespace observability
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization victoria-metrics-k8s-stack --with-source
   flux get kustomizations victoria-metrics-k8s-stack -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease victoria-metrics-k8s-stack -n observability
   ```

#### Phase 3 – Monitor Stack Operations

1. Watch component pods for readiness:

   ```bash
   kubectl get pods -n observability -l app.kubernetes.io/instance=victoria-metrics-k8s-stack
   ```

2. Validate Victoria Metrics custom resources:

   ```bash
   kubectl get vmsingle,vmalert,vmagent,vmalertmanager -n observability
   ```

3. Check Grafana accessibility and datasources:

   ```bash
   kubectl get svc grafana -n observability
   ```

#### Phase 4 – Manual Intervention for Issues

1. Restart failing components if needed:

   ```bash
   kubectl rollout restart deploy/victoria-metrics-k8s-stack-vmsingle -n observability
   ```

2. Inspect alertmanager configuration secrets:

   ```bash
   kubectl describe secret victoria-metrics-k8s-stack-secrets -n observability
   ```

3. Verify etcd scraping with TLS configuration.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization victoria-metrics-k8s-stack -n flux-system
   flux suspend helmrelease victoria-metrics-k8s-stack -n observability
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization victoria-metrics-k8s-stack -n flux-system
   flux resume helmrelease victoria-metrics-k8s-stack -n observability
   ```

4. Consider scaling key components to zero as a last resort:

   ```bash
   kubectl -n observability scale deploy/victoria-metrics-k8s-stack-vmsingle --replicas=0
   ```

### Validation

- `kubectl get pods -n observability` shows all stack components running and ready.
- `kubectl get vmsingle -n observability` reports VMSingle ready with storage.
- `kubectl get svc grafana -n observability` provides access to Grafana UI.
- `flux get helmrelease victoria-metrics-k8s-stack -n observability` reports `Ready=True` with no pending upgrades.
- Metrics are collected from nodes, pods, and etcd.

### Troubleshooting Guidance

- If VMSingle fails to start, check PVC binding and storage class.
- For scraping issues, verify service discovery and TLS configurations.
- When Grafana datasources fail, check Victoria Metrics endpoints.
- If alerts don't fire, inspect VMAlert and Alertmanager configurations.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                                | Purpose                                                              |
| ------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `task validate`                                                     | Runs repository schema validation (kubeconform, yamllint, conftest). |
| `task dev-env:lint`                                                 | Executes markdownlint, prettier, and ancillary linters.              |
| `flux diff hr victoria-metrics-k8s-stack --namespace observability` | Previews rendered Helm changes before reconciliation.                |
| `kubectl -n observability get events --sort-by=.lastTimestamp`      | Confirms component startup and reconciliation events.                |
| `kubectl get vmsingle -n observability`                             | Validates metrics storage availability.                              |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Victoria Metrics operator: [cluster/apps/observability/victoria-metrics-operator/README.md](../victoria-metrics-operator/README.md)
- Secret writer: [cluster/apps/observability/victoria-metrics-secret-writer/README.md](../victoria-metrics-secret-writer/README.md)
- Upstream Victoria Metrics k8s stack: <https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/>
- Grafana configuration: <https://grafana.com/docs/grafana/latest/>
