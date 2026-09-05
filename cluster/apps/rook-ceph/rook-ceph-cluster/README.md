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

#### Stable Interface Matching with Link Aliases

Thunderbolt interface names (`thunderbolt0`, `thunderbolt1`) are **not stable across reboots** -- they depend on kernel enumeration order. The bus path is stable, so `talos/patches/worker/10-configure-thunderbolt-aliases.yaml` pins an alias to each bus path, and the per-node link configs address the aliases rather than kernel names:

```yaml
apiVersion: v1alpha1
kind: LinkAliasConfig
name: ethSel0
selector:
  match: glob("0-1.0", link.bus_path)
```

```yaml
apiVersion: v1alpha1
kind: LinkConfig
name: ethSel0
mtu: 65520
addresses:
  - address: 169.254.255.101/32
routes:
  - destination: 169.254.255.102/32
    metric: 2048
```

Every MS-01 is cabled identically, so the same alias points at a different peer on each node:

| Node    | ethSel0 (bus path 0-1.0) -> | ethSel1 (bus path 1-1.0) -> |
| ------- | --------------------------- | --------------------------- |
| ms-01-1 | ms-01-2                     | ms-01-3                     |
| ms-01-2 | ms-01-1                     | ms-01-3                     |
| ms-01-3 | ms-01-1                     | ms-01-2                     |

#### LAN Fallback Routes

The ring gives each node exactly one direct path to each peer. Without a second path, a single failed link black-holes OSD replication between the two nodes on either end of it. Each node therefore carries a `metric: 4096` route to both peers via the node LAN, defined alongside the VLAN config in `talos/patches/node/ms-01-*/03-configure-vlan.yaml.tpl`. These stay dormant while the direct
`metric: 2048` routes exist.

Two non-obvious requirements make this work:

- Each fallback route pins `source` to the node's own ring address. Ceph leaves outgoing connections unbound because `ms_bind_before_connect` defaults to `false`, so without an explicit prefsrc the detour would be sourced from the node's VLAN address and arrive outside the configured cluster network.
- `net.ipv4.conf.{all,default}.ignore_routes_with_linkdown` is set to `1` in `talos/patches/worker/02-tune-networking.yaml`. A Thunderbolt netdev that loses carrier while still `IFF_UP` keeps its route, and the kernel would otherwise keep selecting that dead low-metric path.

This only covers a link that is fully **down**. A link that stays up while corrupting frames keeps its low-metric route and continues to be preferred -- see Troubleshooting.

#### OSD Down Reporting

`mon_osd_min_down_reporters` is lowered to `1` in `values.yaml`. The Ceph default of `2` cannot be met on this topology: with one OSD per host and a point-to-point cluster network, a single ring link failure is only visible to the two OSDs on either end, giving one reporter each, while the third OSD reaches both peers and never reports. At the default the mons never mark anyone down and writes to
the affected PGs block indefinitely instead of peering on the surviving two replicas.

#### Verifying Thunderbolt Connectivity

Check alias, state and MTU on the ring links. A healthy link reports `OPER STATE` of `up` at MTU 65520 with its alias applied:

```bash
talosctl -n ms-01-1 get links
talosctl -n ms-01-1 get addresses
```

> **`LINK STATE` reads `false` on healthy ring links.** `thunderbolt-net` implements no ethtool link detection, so `LINK STATE` and `duplex` are reporting artifacts rather than fault indicators -- all six ring links show `false` while the ring is fully healthy. Read `OPER STATE` instead. The driver does maintain real carrier via `netif_carrier_on`/`netif_carrier_off` on tunnel establishment and
> teardown, and that is what `ignore_routes_with_linkdown` keys off, so do not disable that sysctl on the basis of `LINK STATE`.

Confirm the direct routes are present and preferred over the fallbacks:

```bash
talosctl -n ms-01-1 get routes
# Direct ring routes appear at metric 2048; LAN fallbacks at metric 4096
```

Check Ceph is using the cluster network:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd dump | grep -E "^osd\."
# Each OSD lists both a public address and a cluster address in 169.254.255.0/24
```

## Troubleshooting

### CephNodeNetworkPacketErrors flapping on a Thunderbolt link

The alert has no `for:` duration and fires on a ratio of errors to packets, so a marginal ring link produces an alert that clears and re-fires as cluster traffic rises and falls. A quiet link with a low absolute error count still trips the ratio. Treat repeated flapping as a real hardware signal rather than alert noise.

Identify which link is degrading -- errors land on the **receiving** side, so the interface reporting them is the one being sent corrupt frames by its peer:

```bash
# Error rate as a percentage of packets, per ring interface
100 * sum by (instance,device) (rate(node_network_receive_errs_total{device=~"thunderbolt.*"}[5m]))
  / sum by (instance,device) (rate(node_network_receive_packets_total{device=~"thunderbolt.*"}[5m]))
```

Cross-reference `node_network_receive_frame_total` to confirm the errors are framing/CRC rather than drops, and check the kernel log for retimer instability, which points at the cable or connector:

```bash
talosctl -n ms-01-1 dmesg | grep -i thunderbolt
# Repeated "retimer disconnected" / "new retimer found" indicates a marginal physical link
```

Reseating a marginal cable can make it substantially worse -- compare the error ratio before and after. A cable that degrades on reseat needs replacing, not reseating.

### Ring link down and OSD traffic stalled

A ring link that comes back after a hotplug may re-enumerate without its config: the alias is lost, MTU reverts to 1500 and the ring address is missing, so the peer route is withdrawn and never restored. Compare against the healthy state in Verifying Thunderbolt Connectivity above. Rebooting the affected node restores the link.

Before pulling a ring cable deliberately, set `noout` and `nodown` to stop rebalancing and OSD flapping, and unset both afterwards. Note that `nodown` also prevents Ceph from routing around a genuinely dead peer, so do not leave it set if the link does not come back.

If both ring links on a node go away as netdevs rather than merely losing carrier, the kernel rejects the fallback routes because their prefsrc is no longer local. Talos collects that into the `RouteSpecController` error path, so the whole reconcile pass fails and enters restart backoff. It self-heals once a link returns -- a flapping route controller during a dual-link failure is a symptom, not a
second fault.

## References

- [Rook Ceph documentation](https://rook.io/docs/rook/latest/)
- [Rook Ceph cluster Helm chart](https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph-cluster)
