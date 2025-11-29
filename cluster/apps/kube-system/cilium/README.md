# cilium Runbook

## Purpose and Scope

The cilium deployment provides the Container Network Interface (CNI) and network policy engine for the Kubernetes cluster. It includes advanced networking features such as BGP control plane for routing, Hubble for observability, Gateway API support, and kube-proxy replacement for improved performance and security.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the Cilium CNI healthy.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                          | Description                                                                |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/kube-system/README.md`                          | This runbook and component overview.                                       |
| `cluster/apps/kube-system/kustomization.yaml`                 | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/kube-system/cilium/ks.yaml`                     | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/kube-system/cilium/app/kustomization.yaml`      | Overlay combining the HelmRelease, ConfigMap, and BGP resources.           |
| `cluster/apps/kube-system/cilium/app/release.yaml`            | Flux `HelmRelease` referencing the Cilium Helm chart.                      |
| `cluster/apps/kube-system/cilium/app/values.yaml`             | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/kube-system/cilium/app/kustomizeconfig.yaml`    | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/apps/kube-system/cilium/app/bgp-cluster.yaml`        | BGP cluster configuration for routing announcements.                       |
| `cluster/apps/kube-system/cilium/app/bgp-peer.yaml`           | BGP peer definitions for external routers.                                 |
| `cluster/apps/kube-system/cilium/app/bgp-advertisements.yaml` | BGP advertisement policies for service and pod CIDRs.                      |
| `cluster/apps/kube-system/cilium/app/cluster-lb-ip-pool.yaml` | LoadBalancer IP pool configuration.                                        |
| `cluster/flux/meta/repositories/cilium-charts.yaml`           | Helm repository definition pinning the upstream Cilium source.             |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage CNI and network policies.
- Ensure the workstation can reach the Kubernetes API and that the `cilium` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- BGP peers and routing infrastructure must be configured for BGP features.

## Operational Runbook

### Summary

Operate the cilium Helm release to maintain cluster networking, including CNI functionality, network policies, BGP routing, and observability through Hubble.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when CNI updates could impact pod networking.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n kube-system get helmrelease cilium -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/kube-system/cilium/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr cilium --namespace kube-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization cilium --with-source
   flux get kustomizations cilium -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease cilium -n kube-system
   ```

#### Phase 3 – Monitor CNI Health

1. Watch Cilium pods and status:

   ```bash
   kubectl get pods -n kube-system -l k8s-app=cilium
   cilium status
   ```

2. Validate BGP peering and routing:

   ```bash
   cilium bgp peers
   cilium bgp routes
   ```

3. Check Hubble connectivity:

   ```bash
   hubble status
   ```

#### Phase 4 – Manual Intervention for Network Issues

1. Inspect Cilium logs for connectivity problems:

   ```bash
   kubectl logs -n kube-system ds/cilium
   ```

2. Check node network policies and endpoints:

   ```bash
   cilium endpoint list
   cilium policy get
   ```

3. Restart Cilium daemonset if needed:

   ```bash
   kubectl rollout restart ds/cilium -n kube-system
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization cilium -n flux-system
   flux suspend helmrelease cilium -n kube-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization cilium -n flux-system
   flux resume helmrelease cilium -n kube-system
   ```

4. Consider draining nodes for major CNI changes as a last resort.

### Validation

- `cilium status` reports all nodes ready and connected.
- `kubectl get nodes` shows all nodes Ready with network connectivity.
- `flux get helmrelease cilium -n kube-system` reports `Ready=True` with no pending upgrades.
- BGP peers show established state and routes are advertised correctly.

### Troubleshooting Guidance

- If pods cannot communicate, check Cilium network policies and endpoint status:

  ```bash
  cilium endpoint list
  cilium policy get
  ```

- For BGP issues, verify peer configurations and routing tables:

  ```bash
  cilium bgp peers
  ip route show
  ```

- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr cilium --namespace kube-system
  kubeconform -strict -summary ./cluster/apps/kube-system/cilium/app
  ```

- If Cilium pods crash, capture logs and describe the pod:

  ```bash
  kubectl -n kube-system get pods
  kubectl -n kube-system describe pod <pod-name>
  ```

- For Hubble issues, consult Hubble documentation and check relay/UI pods.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                          | Purpose                                                                                          |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                               | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                           | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr cilium --namespace kube-system` | Previews rendered Helm changes before reconciliation.                                            |
| `cilium status`                               | Validates CNI health and node connectivity.                                                      |
| `kubectl get nodes`                           | Confirms all nodes are network-ready.                                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Upstream Cilium documentation: <https://docs.cilium.io/>
- BGP control plane documentation: <https://docs.cilium.io/en/stable/network/bgp/>
- Hubble documentation: <https://docs.cilium.io/en/stable/observability/hubble/>
