# chrony Runbook

## Purpose and Scope

The chrony controller provides Network Time Protocol (NTP) time synchronization services for the spruyt-labs cluster.

It deploys a highly available NTP server using the dockurr/chrony image, configured to synchronize with upstream NTP servers (time.cloudflare.com) and serve NTP requests to cluster nodes and workloads via a LoadBalancer service.

This ensures accurate timekeeping across the cluster, which is critical for logging, security, and distributed system operations.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                    |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `cluster/apps/chrony/chrony/README.md`                            | This runbook and component overview.                                           |
| `cluster/apps/chrony/kustomization.yaml`                          | Top-level Kustomize entry that namespaces resources and delegates to Flux.     |
| `cluster/apps/chrony/namespace.yaml`                              | Namespace definition for the chrony workload.                                  |
| `cluster/apps/chrony/chrony/ks.yaml`                              | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.        |
| `cluster/apps/chrony/chrony/app/kustomization.yaml`               | Overlay combining the HelmRelease and generated values ConfigMap.              |
| `cluster/apps/chrony/chrony/app/release.yaml`                     | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.              |
| `cluster/apps/chrony/chrony/app/values.yaml`                      | Rendered values supplied to the chart via ConfigMap.                           |
| `cluster/apps/chrony/chrony/app/kustomizeconfig.yaml`             | Remaps ConfigMap keys to Helm values for deterministic patches.                |
| `cluster/flux/meta/repositories/oci/bjw-s-labs-app-template.yaml` | OCI repository definition pinning the upstream bjw-s-labs app-template source. |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage cluster time synchronization.
- Ensure the workstation can reach the Kubernetes API and that the `chrony` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Confirm that the NTP LoadBalancer IP (`${NTP_IP4}`) is available and configured in the cluster networking.

## Operational Runbook

### Summary

Operate the chrony Helm release to provide reliable NTP services, ensuring cluster nodes and workloads maintain accurate time synchronization. The deployment uses 3 replicas for high availability and serves NTP on UDP port 123 via a LoadBalancer service.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when time synchronization disruptions could impact cluster operations.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n chrony get helmrelease chrony -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/chrony/chrony/app/` as required (e.g., NTP servers, replicas, resource limits).
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr chrony --namespace chrony
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization chrony --with-source
   flux get kustomizations chrony -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease chrony -n chrony
   ```

#### Phase 3 – Monitor Time Synchronization

1. Verify NTP service availability:

   ```bash
   kubectl -n chrony get svc chrony
   ntpq -p ${NTP_IP4}
   ```

2. Check chrony synchronization status on pods:

   ```bash
   kubectl -n chrony exec -it deploy/chrony -- chronyc tracking
   kubectl -n chrony exec -it deploy/chrony -- chronyc sources
   ```

3. Ensure pods are ready and probes are passing (`kubectl get pods -n chrony`).

#### Phase 4 – Manual Intervention for Time Sync Issues

1. If synchronization fails, inspect chrony logs for errors:

   ```bash
   kubectl -n chrony logs deploy/chrony
   ```

2. Manually adjust NTP servers or configuration if upstream sources are unreachable.
3. Restart pods if needed:

   ```bash
   kubectl -n chrony rollout restart deploy/chrony
   ```

4. For persistent issues, verify network connectivity to upstream NTP servers from pod context.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization chrony -n flux-system
   flux suspend helmrelease chrony -n chrony
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization chrony -n flux-system
   flux resume helmrelease chrony -n chrony
   ```

4. Scale the deployment to zero as a last resort during maintenance:

   ```bash
   kubectl -n chrony scale deploy/chrony --replicas=0
   ```

### Validation

- `chronyc tracking` shows synchronized status with low offset and jitter.
- `ntpq -p ${NTP_IP4}` displays reachable peers with '\*' indicating the selected source.
- `kubectl get pods -n chrony` reports all pods as Ready with passing readiness probes.
- `flux get helmrelease chrony -n chrony` reports `Ready=True` with no pending upgrades.
- Cluster nodes and workloads exhibit consistent timestamps in logs and events.

### Troubleshooting Guidance

- If NTP queries fail, verify the LoadBalancer IP is correctly assigned and reachable:

  ```bash
  kubectl -n chrony describe svc chrony
  ping ${NTP_IP4}
  ```

- For synchronization issues, check upstream server reachability:

  ```bash
  kubectl -n chrony exec -it deploy/chrony -- ping time.cloudflare.com
  ```

- If readiness probes fail, inspect chrony configuration and logs:

  ```bash
  kubectl -n chrony exec -it deploy/chrony -- chronyc waitsync 15
  kubectl -n chrony logs deploy/chrony --previous
  ```

- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr chrony --namespace chrony
  kubeconform -strict -summary ./cluster/apps/chrony/chrony/app
  ```

- If pods crash or fail to start, capture pod details:

  ```bash
  kubectl -n chrony get pods
  kubectl -n chrony describe pod <pod-name>
  ```

- For cluster-wide time drift, ensure nodes are configured to use the chrony service as NTP source.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                           | Purpose                                                                                          |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                            | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr chrony --namespace chrony`                       | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n chrony exec -it deploy/chrony -- chronyc tracking` | Confirms chrony synchronization status post-rollout.                                             |
| `ntpq -p ${NTP_IP4}`                                           | Validates NTP service availability and peer synchronization.                                     |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../../cluster/flux/README.md)
- OCI repository management: [cluster/flux/meta/repositories/oci/README.md](../../../../cluster/flux/meta/repositories/oci/README.md)
- Cluster networking and LoadBalancer IPs: [cluster/apps/README.md](../../README.md)
- Upstream chrony documentation: <https://chrony-project.org/>
- Upstream dockurr/chrony image: <https://hub.docker.com/r/dockurr/chrony>
- NTP protocol reference: <https://datatracker.ietf.org/doc/html/rfc5905>
