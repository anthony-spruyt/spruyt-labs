# traefik Runbook

## Purpose and Scope

The traefik deployment provides the Traefik ingress controller for the Kubernetes cluster, handling HTTP/HTTPS routing, load balancing, and SSL termination. It integrates with Kubernetes CRDs for dynamic configuration and supports Gateway API for advanced routing features.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the Traefik ingress controller healthy.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                  | Description                                                                        |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `cluster/apps/traefik/README.md`                      | This runbook and component overview.                                               |
| `cluster/apps/traefik/kustomization.yaml`             | Top-level Kustomize entry that namespaces resources and delegates to Flux.         |
| `cluster/apps/traefik/namespace.yaml`                 | Namespace definition for the traefik workload.                                     |
| `cluster/apps/traefik/traefik/ks.yaml`                | Flux `Kustomization` driving reconciliation of the HelmRelease and ingress routes. |
| `cluster/apps/traefik/traefik/app/kustomization.yaml` | Overlay combining the HelmRelease and generated values ConfigMap.                  |
| `cluster/apps/traefik/traefik/app/release.yaml`       | Flux `HelmRelease` referencing the Traefik Helm chart.                             |
| `cluster/apps/traefik/traefik/app/values.yaml`        | Rendered values supplied to the chart via ConfigMap.                               |
| `cluster/apps/traefik/traefik/ingress/`               | Ingress route configurations for various services.                                 |
| `cluster/flux/meta/repositories/traefik-charts.yaml`  | Helm repository definition pinning the upstream Traefik source.                    |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage ingress resources and certificates.
- Ensure the workstation can reach the Kubernetes API and that the `traefik` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Wildcard TLS certificate must be available for SSL termination.

## Operational Runbook

### Summary

Operate the traefik Helm release to maintain ingress routing and load balancing, ensuring secure and efficient traffic handling for cluster services.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when ingress updates could impact service availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n traefik get helmrelease traefik -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/traefik/traefik/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr traefik --namespace traefik
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomizations:

   ```bash
   flux reconcile kustomization traefik --with-source
   flux reconcile kustomization traefik-ingress --with-source
   flux get kustomizations -n flux-system -l app.kubernetes.io/name=traefik
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease traefik -n traefik
   ```

#### Phase 3 – Monitor Ingress Health

1. Watch Traefik pods and services:

   ```bash
   kubectl get pods -n traefik -l app.kubernetes.io/name=traefik
   kubectl get svc -n traefik
   ```

2. Validate ingress routes and certificates:

   ```bash
   kubectl get ingress -A
   kubectl get ingressroute -A
   kubectl get certificates -A
   ```

3. Check Traefik dashboard and metrics:

   ```bash
   kubectl port-forward -n traefik svc/traefik 8080:80
   # Access dashboard at http://localhost:8080/dashboard/
   ```

#### Phase 4 – Manual Intervention for Routing Issues

1. Inspect Traefik logs for routing errors:

   ```bash
   kubectl logs -n traefik deploy/traefik
   ```

2. Check ingress resource status and events:

   ```bash
   kubectl describe ingressroute <name>
   kubectl get events -n traefik --sort-by=.lastTimestamp
   ```

3. Restart Traefik deployment if needed:

   ```bash
   kubectl rollout restart deploy/traefik -n traefik
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization traefik -n flux-system
   flux suspend kustomization traefik-ingress -n flux-system
   flux suspend helmrelease traefik -n traefik
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization traefik -n flux-system
   flux resume kustomization traefik-ingress -n flux-system
   flux resume helmrelease traefik -n traefik
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n traefik scale deploy/traefik --replicas=0
   ```

### Validation

- `kubectl get svc -n traefik` shows traefik service with external IP.
- `kubectl get pods -n traefik -l app.kubernetes.io/name=traefik` reports Running pods.
- `flux get helmrelease traefik -n traefik` reports `Ready=True` with no pending upgrades.
- HTTPS endpoints are accessible and certificates are valid.

### Troubleshooting Guidance

- If ingress routes are not working, check Traefik configuration and CRD support:

  ```bash
  kubectl get ingressroute -A -o yaml
  ```

- For SSL issues, verify certificate secrets and TLS store configuration:

  ```bash
  kubectl get secret -n traefik wildcard-${EXTERNAL_DOMAIN/./-}-tls
  ```

- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr traefik --namespace traefik
  kubeconform -strict -summary ./cluster/apps/traefik/traefik/app
  ```

- If pods crash, capture logs and describe the pod:

  ```bash
  kubectl -n traefik get pods
  kubectl -n traefik describe pod <pod-name>
  ```

- For performance issues, monitor Traefik metrics and adjust resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                     | Purpose                                                                                          |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                          | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                      | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr traefik --namespace traefik`               | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n traefik get events --sort-by=.lastTimestamp` | Confirms Traefik emits healthy events after rollout.                                             |
| `kubectl get ingressroute -A`                            | Validates ingress routes are properly configured.                                                |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../flux/README.md)
- Helm repository management: [cluster/flux/meta/repositories/README.md](../../../flux/meta/repositories/README.md)
- Traefik documentation: <https://doc.traefik.io/traefik/>
- Traefik Helm chart: <https://github.com/traefik/traefik-helm-chart>
- Kubernetes Gateway API: <https://gateway-api.sigs.k8s.io/>
