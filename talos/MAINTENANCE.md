# Talos Maintenance Procedures

## Overview

This document outlines maintenance procedures for the spruyt-labs Talos cluster, including node management, cluster upgrades, backup operations, and disaster recovery. These procedures ensure high availability and data integrity during maintenance windows.

## Node Management

### Adding New Nodes

#### Node Addition Prerequisites

- Hardware meets requirements (see cluster bootstrap documentation)
- Network configuration prepared (IP, VLAN, DNS)
- Talos schematic selected for hardware type

#### Node Addition Procedure

1. **Update Talos Configuration**:

   ```bash
   # Edit talos/talconfig.yaml to add new node
   vim talos/talconfig.yaml
   ```

1. **Generate Machine Config**:

   ```bash
   talhelper genconfig
   ```

1. **Provision Hardware**:

   - Boot with appropriate Talos ISO
   - Apply configuration:

   ```bash
   talosctl apply-config --insecure --nodes <new-node-ip> \
     --file talos/clusterconfig/<hostname>.yaml
   ```

1. **Verify Node Join**:

   ```bash
   kubectl get nodes
   talosctl health --nodes <new-node-ip>
   ```

1. **Update Flux Manifests** if needed for node-specific configurations

#### Node Addition Validation

- Node reports Ready status
- Talos health checks pass
- Flux reconciliation completes
- Storage pools rebalance (if applicable)

### Removing Nodes

#### Node Removal Prerequisites

- Maintenance window scheduled
- Workloads drained from node
- Storage data migrated (if storage node)

#### Node Removal Procedure

1. **Drain Workloads**:

   ```bash
   kubectl cordon <node-name>
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

1. **Migrate Storage Data** (for storage nodes):

   ```bash
   # Set Ceph maintenance flags
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd set noout
   # Wait for data rebalancing
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
   ```

1. **Remove from Talos Configuration**:

   ```bash
   # Edit talos/talconfig.yaml to remove node
   vim talos/talconfig.yaml
   talhelper genconfig
   ```

1. **Shutdown Node**:

   ```bash
   talosctl shutdown -n <node-ip>
   ```

1. **Clean Up**:

   ```bash
   kubectl delete node <node-name>
   # Remove from DNS, DHCP, inventory
   ```

#### Node Removal Validation

- Node removed from cluster
- No orphaned resources
- Storage healthy after rebalancing
- Applications remain available

## Cluster Upgrades

### Talos OS Upgrades

#### Talos Upgrade Prerequisites

- Maintenance window scheduled
- All nodes healthy
- Backup of etcd and critical data
- Upgrade path validated in staging

#### Talos Upgrade Procedure

1. **Pre-Upgrade Validation**:

   ```bash
   talosctl health
   talosctl version --nodes <all-nodes>
   ```

1. **Select Upgrade Image**:

   - Visit <https://factory.talos.dev/>
   - Choose appropriate schematic for hardware
   - Note the full image URL

1. **Upgrade Control Plane** (one node at a time):

   ```bash
   talosctl upgrade \
     --nodes <cp-node-ip> \
     --endpoints <cluster-endpoint> \
     --image <factory-image-url>
   ```

1. **Verify Control Plane**:

   ```bash
   talosctl health --nodes <cp-node-ip>
   kubectl get nodes
   ```

1. **Upgrade Workers** (one at a time, wait for Ceph `HEALTH_OK` between each):

   ```bash
   talosctl upgrade \
     --nodes <worker-node-ip> \
     --endpoints <cluster-endpoint> \
     --image <factory-image-url>

   # Wait for Ceph before next worker
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
   ```

1. **Post-Upgrade Validation**:

   ```bash
   talosctl version --nodes <all-nodes>
   kubectl get nodes
   flux get kustomizations
   ```

#### Rollback

- Revert to previous Talos version using same upgrade command with older image
- Monitor for regressions during rollback window

### Kubernetes Upgrades

#### Kubernetes Upgrade Prerequisites

- Compatible Talos version
- All nodes healthy
- etcd backup current
- Maintenance window approved

#### Kubernetes Upgrade Procedure

1. **Dry Run**:

   ```bash
   talosctl upgrade-k8s -n {NODE_IP} --to <version> --dry-run
   ```

1. **Execute Upgrade**:

   ```bash
   talosctl upgrade-k8s -n {NODE_IP} --to <version>
   ```

1. **Monitor Progress**:

   ```bash
   kubectl get nodes
   talosctl health
   ```

1. **Verify Components**:

   ```bash
   kubectl version --short
   flux get kustomizations
   ```

## Backup Operations

### etcd Backups

#### Automatic

- Daily snapshots via Talos
- Stored locally on control plane nodes

#### Manual

```bash
talosctl etcd snapshot <snapshot-path>
```

#### etcd Backup Validation

- Snapshot files exist and are recent
- Snapshot integrity verified
- Restore procedure tested

## Disaster Recovery

### Cluster Recovery

#### Complete Cluster Loss

1. **Assess Damage**:

   - Identify surviving nodes
   - Check data availability

1. **Rebuild Control Plane**:

   ```bash
   # Bootstrap from surviving node or etcd snapshot
   talosctl bootstrap --nodes <surviving-cp>
   ```

1. **Restore etcd** (if needed):

   ```bash
   talosctl etcd snapshot restore <snapshot-path>
   ```

1. **Rejoin Nodes**:

   - Reapply configurations
   - Verify cluster reformation

#### Single Node Failure

1. **Replace Hardware**
1. **Reprovision Node** (see Adding New Nodes)
1. **Restore Data** from backups/replicas

## Monitoring and Alerting

### Health Checks

- Node readiness: `kubectl get nodes`
- Talos health: `talosctl health`
- Storage health: `ceph status`
- Backup status: `velero backup get`

### Maintenance Windows

- Schedule during low-usage periods
- Notify stakeholders in advance
- Document all changes and outcomes
- Post-maintenance validation

## References

- [Talos Upgrade Guide](https://docs.siderolabs.com/talos/v1.13/configure-your-talos-cluster/lifecycle-management/upgrading-talos)
- [Kubernetes Upgrade Guide](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [Ceph Maintenance](https://rook.io/docs/rook/latest/Storage-Configuration/Ceph-CSI/ceph-csi-drivers/)
