# mosquitto Runbook

## Purpose and Scope

The mosquitto controller deploys an Eclipse Mosquitto MQTT broker for IoT and messaging applications in the spruyt-labs environment. It provides secure MQTT (port 1883) and MQTT-SSL (port 8883) endpoints with password-based authentication, TLS encryption, and persistent message storage. This readme documents the GitOps layout, deployment workflow, and operations required to keep the MQTT broker healthy.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                | Description                                                                |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/mosquitto/README.md`                                  | Parent runbook and component overview.                                     |
| `cluster/apps/mosquitto/kustomization.yaml`                         | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/mosquitto/namespace.yaml`                             | Namespace definition for the mosquitto workload.                           |
| `cluster/apps/mosquitto/mosquitto/ks.yaml`                          | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/mosquitto/mosquitto/app/kustomization.yaml`           | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/mosquitto/mosquitto/app/release.yaml`                 | Flux `HelmRelease` referencing the bjw-s app-template chart.               |
| `cluster/apps/mosquitto/mosquitto/app/values.yaml`                  | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/mosquitto/mosquitto/app/kustomizeconfig.yaml`         | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/apps/mosquitto/mosquitto/app/certificate.yaml`             | Certificate manifest for TLS.                                              |
| `cluster/apps/mosquitto/mosquitto/app/persistent-volume-claim.yaml` | PVC for persistent data storage.                                           |
| `cluster/flux/meta/repositories/bjw-s-labs-app-template.yaml`       | Helm repository definition pinning the upstream bjw-s app-template source. |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage MQTT broker configurations.
- Ensure the workstation can reach the Kubernetes API and that the `mosquitto` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Verify that required secrets (mosquitto-secrets, TLS certificates) exist in the cluster.

## Operational Runbook

### Summary

Operate the mosquitto Helm release to provide reliable MQTT messaging services with authentication, encryption, and persistence for IoT applications.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when broker downtime could impact connected clients.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n mosquitto get helmrelease mosquitto -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/mosquitto/mosquitto/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr mosquitto --namespace mosquitto
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization mosquitto --with-source
   flux get kustomizations mosquitto -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease mosquitto -n mosquitto
   ```

#### Phase 3 – Monitor Broker Operations

1. Watch pod logs for connection and authentication events:

   ```bash
   kubectl logs -n mosquitto deploy/mosquitto -f
   ```

2. Validate service endpoints and connectivity:

   ```bash
   kubectl get svc -n mosquitto
   ```

3. Check persistent volume claims for data retention:

   ```bash
   kubectl get pvc -n mosquitto
   ```

#### Phase 4 – Manual Intervention for Issues

1. Restart pods if authentication or connection issues occur:

   ```bash
   kubectl rollout restart deploy/mosquitto -n mosquitto
   ```

2. Inspect secrets and certificates for expiration or misconfiguration:

   ```bash
   kubectl describe secret mosquitto-secrets -n mosquitto
   kubectl describe certificate mosquitto-lan-<domain>-tls -n mosquitto
   ```

3. For client connection failures, verify password file and TLS setup in logs.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization mosquitto -n flux-system
   flux suspend helmrelease mosquitto -n mosquitto
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization mosquitto -n flux-system
   flux resume helmrelease mosquitto -n mosquitto
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n mosquitto scale deploy/mosquitto --replicas=0
   ```

### Validation

- `kubectl get pods -n mosquitto` shows mosquitto pod running and ready.
- `kubectl get svc -n mosquitto` reports LoadBalancer service with assigned IP.
- `kubectl get pvc -n mosquitto` shows mosquitto-data PVC bound.
- `flux get helmrelease mosquitto -n mosquitto` reports `Ready=True` with no pending upgrades.
- MQTT clients can connect using credentials from mosquitto-secrets.

### Troubleshooting Guidance

- If pods fail to start, check init container logs for secret copying issues:

  ```bash
  kubectl logs -n mosquitto deploy/mosquitto -c copy-secrets
  ```

- For authentication failures, verify the password file format and client credentials.
- When TLS connections fail, inspect certificate validity and listener configuration.
- If persistence is lost, check PVC binding and rook-ceph cluster health.
- For high resource usage, review connection limits and message retention settings.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                       | Purpose                                                              |
| ---------------------------------------------------------- | -------------------------------------------------------------------- |
| `task validate`                                            | Runs repository schema validation (kubeconform, yamllint, conftest). |
| `task dev-env:lint`                                        | Executes markdownlint, prettier, and ancillary linters.              |
| `flux diff hr mosquitto --namespace mosquitto`             | Previews rendered Helm changes before reconciliation.                |
| `kubectl -n mosquitto get events --sort-by=.lastTimestamp` | Confirms broker startup events and connection logs.                  |
| `kubectl get nodes`                                        | Validates cluster readiness for LoadBalancer services.               |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Rook Ceph storage operations: [cluster/apps/rook-ceph/rook-ceph-cluster/README.md](../../../../cluster/apps/rook-ceph/rook-ceph-cluster/README.md)
- Certificate management: [cluster/apps/cert-manager/cert-manager/README.md](../../../../cluster/apps/cert-manager/cert-manager/README.md)
- Upstream Eclipse Mosquitto documentation: <https://mosquitto.org/>
- bjw-s app-template chart: <https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common>
