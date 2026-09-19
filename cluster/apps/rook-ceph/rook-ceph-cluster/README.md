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

### Receive errors on a Thunderbolt ring link

Do not read the aggregate `node_network_receive_errs_total` as a wire-fault signal on these interfaces. The `thunderbolt-net` driver sums five unrelated sub-counters into it (`tbnet_get_stats64`), and on a healthy ring the dominant contributor is `rx_missed_errors` -- roughly 84% of the total across all three nodes when last measured.

That counter increments in `tbnet_check_frame` when a fragment arrives out of sequence. At MTU 65520 a single packet spans many frames, so one dropped fragment invalidates every remaining fragment of that packet and inflates the count by a large multiple. It is receive-path sequencing under load, not corruption. The same contamination reaches the drop column in `/proc/net/dev`, which sums
`rx_dropped` with `rx_missed_errors` -- sysfs `rx_dropped` can read 0 while node-exporter reports over a thousand.

Both Ceph packet alerts therefore exclude `thunderbolt*`, and the ring is covered by `ThunderboltRingFrameErrors` in the observability `vmrules/` directory.

That rule watches `node_network_receive_frame_total`, which is the least contaminated counter node-exporter exposes here but is **not** corruption-only. Under the default legacy mapping node-exporter computes it as `rx_frame_errors + rx_length_errors + rx_over_errors + rx_crc_errors`, and this driver never writes `rx_frame_errors` at all. Its thresholds are calibrated against a 30 day replay of
this ring rather than derived from the counter's nominal meaning, so recalibrate them after any change to ring MTU, node count or node-exporter netdev flags.

The rule gates on a minimum packet rate, so a link carrying very little traffic sits outside it and will not alert regardless of its error ratio -- inherent to ratio alerting, and the reason the ring's quietest interface is effectively uncovered. Check such a link by hand using the counter split below rather than relying on the alert.

Split the aggregate before drawing any conclusion:

```bash
for c in rx_errors rx_crc_errors rx_length_errors rx_over_errors rx_missed_errors; do
  echo "$c = $(talosctl -n ms-01-3 read /sys/class/net/thunderbolt1/statistics/$c)"
done
```

Only `rx_crc_errors` is unambiguously physical -- `tbnet_check_frame` sets it solely from the `RING_DESC_CRC_ERROR` hardware descriptor flag. `rx_missed_errors` and `rx_over_errors` mean the receive path could not keep up. `rx_length_errors` is ambiguous and should not be read as a hardware signal on its own: the driver increments it at five sites, including the mid-packet `frame_count` mismatch
and the `TBNET_MAX_MTU` overflow check, which belong to the same jumbo-frame cascade that drives `rx_missed_errors`.

Confirm link health independently before suspecting a cable -- a degrading cable negotiates fewer lanes or a lower speed, and logs retimer instability:

```bash
talosctl -n ms-01-1 read /sys/bus/thunderbolt/devices/0-1/rx_speed   # expect 20.0 Gb/s
talosctl -n ms-01-1 read /sys/bus/thunderbolt/devices/0-1/rx_lanes   # expect 2
talosctl -n ms-01-1 dmesg | grep -i thunderbolt
# Repeated "retimer disconnected" / "new retimer found" indicates a marginal physical link
```

Errors land on the **receiving** side, so the peer transmitting into the reporting port shares the suspect segment. Map the ring from the `new host found` lines in the kernel log rather than assuming which cable joins which pair.

Reseating a marginal cable can make it substantially worse -- compare `rx_crc_errors` before and after. A cable that degrades on reseat needs replacing, not reseating.

### Ring link down and OSD traffic stalled

A ring link that comes back after a hotplug may re-enumerate without its config: the alias is lost, MTU reverts to 1500 and the ring address is missing, so the peer route is withdrawn and never restored. Compare against the healthy state in Verifying Thunderbolt Connectivity above. Rebooting the affected node restores the link.

Before pulling a ring cable deliberately, set `noout` and `nodown` to stop rebalancing and OSD flapping, and unset both afterwards. Note that `nodown` also prevents Ceph from routing around a genuinely dead peer, so do not leave it set if the link does not come back.

If both ring links on a node go away as netdevs rather than merely losing carrier, the kernel rejects the fallback routes because their prefsrc is no longer local. Talos collects that into the `RouteSpecController` error path, so the whole reconcile pass fails and enters restart backoff. It self-heals once a link returns -- a flapping route controller during a dual-link failure is a symptom, not a
second fault.

## References

- [Rook Ceph documentation](https://rook.io/docs/rook/latest/)
- [Rook Ceph cluster Helm chart](https://github.com/rook/rook/tree/master/deploy/charts/rook-ceph-cluster)
