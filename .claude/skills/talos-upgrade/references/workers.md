# Phase 4: Worker Upgrades

Commands for Steps 4.1 to 4.6. The gates, including the "Ceph ready" definition, are in the skill. Drain strategy (Step 4.3, Step 4.3a): [worker-drain.md](worker-drain.md). Kata check (Step 4.4a): [kata.md](kata.md). Ceph recovery detail (Step 4.5, Step 4.5a): [ceph-recovery.md](ceph-recovery.md).

## Step 4.1: Pre-node Ceph check (BLOCKING)

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree
```

`BLUESTORE_SLOW_OP_ALERT` stays raised for `bluestore_slow_ops_warn_lifetime` (24h default) after a single slow op and clears when the OSD restarts, so it is acceptable only while all OSDs are up/in and all PGs are `active+clean`. Note it in the progress comment and do not restart OSDs to clear it. Live `SLOW_OPS` (slow requests) still blocks.

If Ceph is not ready, stop and tell the owner with the WORKER UPGRADE BLOCKED report ([templates.md](templates.md)).

## Step 4.2: Get worker info

Get the schematic from a live worker node, as in [Schematic Discovery](discovery.md#schematic-discovery):

```bash
# Get worker node IPs
WORKER_NODES=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

# Get schematic from a live worker node (see Schematic Discovery)
WORKER_IP=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
SCHEMATIC=$(talosctl get extensions -n "${WORKER_IP:?}" 2>/dev/null | grep schematic | awk '{print $NF}')

echo "Worker nodes: ${WORKER_NODES}"
echo "Schematic: ${SCHEMATIC}"
```

## Step 4.3: Execute upgrade

Default drain is fine when the Phase 1 PDB survey came back clean. `<cp-node-ip>` is any control plane node IP (`CP_NODES` in Step 3.1):

```bash
talosctl upgrade \
  --nodes <node-ip> \
  --endpoints <cp-node-ip> \
  --image factory.talos.dev/metal-installer-secureboot/<schematic>:<target-version>
```

Read Step 4.3 in [worker-drain.md](worker-drain.md) before adding `--drain=false`.

## Step 4.4: Wait for node recovery

```bash
# Wait for node to become Ready (timeout: 5 minutes)
kubectl wait --for=condition=Ready node/<hostname> --timeout=300s

# Verify Talos API is responsive
talosctl health -n <node-ip>
```

## Step 4.5: Wait for Ceph recovery

```bash
# Poll until Ceph is ready as defined in Step 4.1 (timeout: 30 minutes)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
```

Expect `HEALTH_WARN` for a few minutes after the reboot, including the NOOUT flag after PGs are clean. Stale heartbeat warnings (`OSD_SLOW_PING_TIME_*`) decay on their own: judge safety by data state, not the `HEALTH_OK` string, and prefer waiting over restarting an OSD. The recovery timeline, the heartbeat checks and the only case that warrants an OSD restart are in [ceph-recovery.md](ceph-recovery.md).

## Step 4.6: Post progress to issue

Post progress to the issue after each worker, including Ceph recovery time, with node names only.
