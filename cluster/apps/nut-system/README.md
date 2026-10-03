# NUT System - UPS Monitoring and Graceful Shutdown

## Overview

Monitors the USB-attached CyberPower CP1500 and, on sustained battery power, shuts the whole cluster down in an order that protects Ceph. Two apps share this namespace:

| App                     | Role                                                                                    |
| ----------------------- | --------------------------------------------------------------------------------------- |
| `nut-server`            | `upsd` + USB driver on the node wired to the UPS, NUT exporter for metrics              |
| `shutdown-orchestrator` | Go service (`cmd/shutdown-orchestrator/`) that polls NUT and runs shutdown and recovery |

## Prerequisites

- **Talos, UPS node**: `talos/patches/node/ms-01-1/04-enable-ups-access.yaml.tpl` sets the `ups.spruyt-labs.io/connected` label and the udev rules that open the USB/hidraw devices. Label and udev rules move together if the UPS is moved to another node.
- **Talos, control plane**: `nut-system` must be in `allowedKubernetesNamespaces` in `talos/patches/control-plane/08-enable-talos-api-access.yaml`. Talos then materialises the `shutdown-orchestrator-talos-secrets` Secret from `shutdown-orchestrator/app/talos-serviceaccount.yaml`; without it the orchestrator pod never starts.
- **NUT config**: `ups.conf`, `upsd.conf`, `upsd.users` and `upsmon.conf` are keys in `nut-server/app/nut-secrets.sops.yaml`, mounted into `/etc/nut/local/`.
- `rook-ceph-tools` must be running; every Ceph step is an exec into it.

## Architecture

```text
UPS --USB--> nut-server (UPS node) --:3493--> LoadBalancer ${NUT_IP4} --> Home Assistant
                  |                                     |
            nut exporter --> vmagent --> UPS* alerts    +--> shutdown-orchestrator (control plane)
                                                                    |
                                                 on battery for SHUTDOWN_DELAY
                                                                    v
                                     noout -> cordon/drain workers -> scale Ceph to 0
                                       -> talosctl shutdown --force (workers, then control plane)
```

## Shutdown Sequence

After `SHUTDOWN_DELAY` seconds on battery (`OB` status):

1. `ceph osd set noout`
2. Cordon workers, then evict workloads on them (excluding `rook-ceph`, `kube-system`, `nut-system`) so RBD mounts are released before storage goes away. If the drain fails, the Ceph scale-down is skipped.
3. Scale Ceph to 0: operator -> MDS -> OSD -> MON -> MGR.
4. Shut down workers concurrently, then control-plane nodes one at a time. The node the orchestrator runs on goes last.

Steps 1-3 are skipped if the remaining UPS budget cannot also cover the node-shutdown phase plus 60s. Node shutdown always runs.

Node shutdown uses Talos with `force: true`, which bypasses PDBs. CNPG is not hibernated first; it recovers from the intact Ceph volumes on the next boot.

### Timing budget

`UPS_RUNTIME_BUDGET` must be at least `SHUTDOWN_DELAY` + the sum of the shutdown phase timeouts (`CEPH_FLAG_PHASE_TIMEOUT`, `DRAIN_PHASE_TIMEOUT`, `CEPH_SCALE_PHASE_TIMEOUT`, `NODE_SHUTDOWN_PHASE_TIMEOUT`); the orchestrator refuses to start otherwise. The values in `shutdown-orchestrator/app/values.yaml` were raised after node shutdowns timed out in practice (#1640). The budget is only safe while
the UPS's reported runtime (`network_ups_tools_battery_runtime`) stays above it - check that metric before adding load to the UPS.

## Operation

### Modes

`MODE` in `shutdown-orchestrator/app/values.yaml` selects the behaviour. Change it in Git and revert it afterwards; leaving the pod in `preflight` or `test` means nothing is watching the UPS.

| Mode        | Behaviour                                                                                                                                            |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `monitor`   | Default. Preflight, recover if needed, then poll the UPS.                                                                                            |
| `preflight` | Validates prerequisites against the live cluster, logs pass/fail, exits.                                                                             |
| `test`      | Runs the **real** shutdown sequence, skipping only its own node, waits for you to power nodes back on, then recovers. Also needs `CONFIRM_TEST=yes`. |

### Recovery

On startup the orchestrator checks for leftover shutdown state (Ceph deployments at 0 replicas, or any CNPG cluster with `cnpg.io/hibernation: "on"`) and runs recovery: wait for the tools pod, scale MON -> MGR -> OSD -> MDS -> operator back to 1, wait for `HEALTH_OK`, unset `noout`, clear CNPG hibernation, uncordon workers.

> The CNPG check does not distinguish a cluster hibernated on purpose. If one is hibernated in Git, every orchestrator restart "recovers" it by clearing the annotation, and Flux sets it back on the next reconcile.

### Manual recovery

If the orchestrator is not running or recovery failed:

```bash
kubectl -n rook-ceph scale deploy -l app=rook-ceph-mon --replicas=1
kubectl -n rook-ceph scale deploy -l app=rook-ceph-mgr --replicas=1
kubectl -n rook-ceph scale deploy -l app=rook-ceph-osd --replicas=1
kubectl -n rook-ceph scale deploy -l app=rook-ceph-mds --replicas=1
kubectl -n rook-ceph scale deploy rook-ceph-operator --replicas=1
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl uncordon ms-01-1 ms-01-2 ms-01-3
```

## Troubleshooting

1. **`upsc` reports "Data stale" or the driver cannot claim the device**

   - **Cause**: UPS cable moved, or the udev rules/label are missing on the node.
   - **Fix**: Re-check the node patch above and that `nut-server` landed on the labelled node.

2. **Recovery fails at `uncordon-workers` with `cannot patch resource "nodes"`**

   - **Cause**: The ClusterRole in `shutdown-orchestrator/app/rbac.yaml` lost `patch` on `nodes` or `list`/`delete` on `pods`. The drain phases need both (#3181).
   - **Impact**: Without them a real shutdown fails cordon and drain, so the Ceph scale-down is skipped and nodes go down with Ceph still running.

## References

- [Network UPS Tools](https://networkupstools.org/)
- [Rook node maintenance](https://rook.io/docs/rook/latest/Upgrade/node-maintenance/)
