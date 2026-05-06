# rook-ceph-cluster - Ceph Storage Cluster

## Overview

Rook Ceph Cluster deploys and manages a Ceph storage cluster using Rook, providing distributed block storage, shared filesystem storage, and object storage for Kubernetes workloads.

## Prerequisites

- Storage devices must be available and properly configured for Ceph OSDs
- rook-ceph-operator deployed

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
| ------- | --------------- |
| ms-01-1 | 169.254.255.101 |
| ms-01-2 | 169.254.255.102 |
| ms-01-3 | 169.254.255.103 |

#### Stable Interface Matching with busPath

Thunderbolt interface names (`thunderbolt0`, `thunderbolt1`) are **not stable across reboots** -- they depend on kernel enumeration order. To ensure consistent routing, the Talos configuration uses `deviceSelector` with `busPath` instead of interface names:

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

| Node    | busPath 0-1.0 -> | busPath 1-1.0 -> |
| ------- | ---------------- | ---------------- |
| ms-01-1 | ms-01-2          | ms-01-3          |
| ms-01-2 | ms-01-1          | ms-01-3          |
| ms-01-3 | ms-01-1          | ms-01-2          |

#### Verifying Thunderbolt Connectivity

Check busPath to peer mapping:

```bash
talosctl -n ms-01-1 read /sys/bus/thunderbolt/devices/0-1/device_name
talosctl -n ms-01-1 read /sys/bus/thunderbolt/devices/1-1/device_name
```

Check Ceph is using the cluster network:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep -E "^osd\."
# Output shows both public (192.168.20.x) and cluster (169.254.255.x) addresses
```

## References

- [Rook Ceph documentation](https://rook.io/docs/rook/latest/)
- [Rook Ceph cluster Helm chart](https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph-cluster)
