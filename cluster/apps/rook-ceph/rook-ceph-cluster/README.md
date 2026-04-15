# rook-ceph-cluster Runbook

## Overview

Rook Ceph Cluster deploys and manages a Ceph storage cluster using Rook, providing distributed block storage, shared filesystem storage, and object storage for Kubernetes workloads. This readme documents the GitOps layout, deployment workflow, and operations for maintaining the Ceph cluster in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage storage clusters.
- Ensure the workstation can reach the Kubernetes API and that the `rook-ceph-cluster` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Storage devices must be available and properly configured for Ceph OSDs.

## Operation

### Summary

Operate the Rook Ceph cluster Helm release to deploy and manage a Ceph storage cluster for persistent storage in Kubernetes.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when storage operations could impact availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n rook-ceph get helmrelease rook-ceph-cluster -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/rook-ceph/rook-ceph-cluster/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr rook-ceph-cluster --namespace rook-ceph
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization rook-ceph-cluster --with-source
   flux get kustomizations rook-ceph-cluster -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease rook-ceph-cluster -n rook-ceph
   ```

#### Phase 3 – Monitor Cluster Health

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n rook-ceph -l app=rook-ceph-mon
   kubectl logs -n rook-ceph deployment/rook-ceph-mgr
   ```

2. Check Ceph cluster status:

   ```bash
   kubectl get cephcluster -n rook-ceph
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
   ```

3. Monitor OSD status:

   ```bash
   kubectl get cephosd -n rook-ceph
   ```

#### Phase 4 – Manual Cluster Operations

1. Check cluster health:

   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health
   ```

2. View cluster details:

   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
   ```

3. Access toolbox for debugging:

   ```bash
   kubectl -n rook-ceph exec -it deployment/rook-ceph-tools -- bash
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization rook-ceph-cluster -n flux-system
   flux suspend helmrelease rook-ceph-cluster -n rook-ceph
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization rook-ceph-cluster -n flux-system
   flux resume helmrelease rook-ceph-cluster -n rook-ceph
   ```

4. Scale deployments to zero as a last resort (not recommended for storage):

   ```bash
   kubectl -n rook-ceph scale deploy/rook-ceph-mgr --replicas=0
   ```

### Validation

- `kubectl get cephcluster -n rook-ceph` shows healthy Ceph clusters.
- `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health` reports HEALTH_OK or HEALTH_WARN.
- `kubectl get storageclass` shows Ceph storage classes available.
- `flux get helmrelease rook-ceph-cluster -n rook-ceph` reports `Ready=True` with no pending upgrades.

### Troubleshooting Guidance

- If cluster health is degraded, check OSD and MON status.
- For storage provisioning issues, verify device availability and configuration.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr rook-ceph-cluster --namespace rook-ceph
  kubeconform -strict -summary ./cluster/apps/rook-ceph/rook-ceph-cluster/app
  ```

- Use the toolbox pod for advanced debugging.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                              | Purpose                                                                                          |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                   | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                               | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr rook-ceph-cluster --namespace rook-ceph`            | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get cephcluster -n rook-ceph`                            | Validates Ceph cluster deployment.                                                               |
| `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status` | Ensures cluster health.                                                                          |

<!-- markdownlint-enable MD013 -->

## Cluster Network Architecture

### Thunderbolt Ring Network

The Ceph cluster uses a dedicated Thunderbolt ring network for OSD-to-OSD traffic (cluster network), separate from the public network used for client I/O. This provides:

- **High bandwidth**: 40Gbps Thunderbolt 4 links between storage nodes
- **Low latency**: Direct point-to-point connections
- **Isolation**: Cluster replication traffic doesn't compete with client traffic

#### Physical Topology

The three MS-01 storage nodes are connected in a ring via Thunderbolt:

```text
        ms-01-1
       /       \
      /         \
 ms-01-2 ───── ms-01-3
```

Each node has two Thunderbolt ports connecting to the other two nodes in a full mesh.

#### Network Configuration

Each node has a link-local IP on the Thunderbolt network:

| Node    | IP Address      |
|---------|-----------------|
| ms-01-1 | 169.254.255.101 |
| ms-01-2 | 169.254.255.102 |
| ms-01-3 | 169.254.255.103 |

#### Stable Interface Matching with busPath

Thunderbolt interface names (`thunderbolt0`, `thunderbolt1`) are **not stable across reboots** - they depend on kernel enumeration order. To ensure consistent routing, the Talos configuration uses `deviceSelector` with `busPath` instead of interface names:

```yaml
- deviceSelector:
    busPath: "0-1.0"  # Stable hardware path
  addresses:
    - 169.254.255.101/32
  routes:
    - network: 169.254.255.102/32
      metric: 2048
```

The busPath values map to physical Thunderbolt connections:

| Node    | busPath 0-1.0 → | busPath 1-1.0 → |
|---------|-----------------|-----------------|
| ms-01-1 | ms-01-2         | ms-01-3         |
| ms-01-2 | ms-01-1         | ms-01-3         |
| ms-01-3 | ms-01-1         | ms-01-2         |

#### Verifying Thunderbolt Connectivity

Check busPath to peer mapping:

```bash
talosctl -n ms-01-1 read /sys/bus/thunderbolt/devices/0-1/device_name
talosctl -n ms-01-1 read /sys/bus/thunderbolt/devices/1-1/device_name
```

Test connectivity between nodes:

```bash
# From ms-01-1, ping ms-01-2 and ms-01-3
kubectl -n dev-debug run ping-test --rm -it --restart=Never --image=busybox \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"ms-01-1"},"hostNetwork":true}}' \
  -- sh -c "ping -c 2 169.254.255.102 && ping -c 2 169.254.255.103"
```

Check Ceph is using the cluster network:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep -E "^osd\."
# Output shows both public (192.168.20.x) and cluster (169.254.255.x) addresses
```

## References

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Storage operations: [cluster/apps/README.md](../../README.md)
- Rook Ceph documentation: <https://rook.io/docs/rook/latest/>
- Rook Ceph cluster Helm chart: <https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph-cluster>
