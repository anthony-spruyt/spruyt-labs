# Phase 4: Worker Upgrades

Commands for Steps 4.1 to 4.6. The gates, including the "Ceph ready" definition, are in the skill. Drain strategy (Step 4.3, Step 4.3a): [worker-drain.md](worker-drain.md). Kata check (Step 4.4a): [kata.md](kata.md). GPU gate (Step 4.4b, also the Phase 1 baseline): below. Ceph recovery detail (Step 4.5, Step 4.5a): [ceph-recovery.md](ceph-recovery.md).

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

## Step 4.4b: GPU gate (each ms-01, BLOCKING)

The llm-tool-guard scanner runs on the ms-01 Intel iGPU, and a later drain can land its pods on any ms-01. After each ms-01 upgrade, and for every ms-01 in Phase 1 as the baseline, prove the GPU works on that node itself. A scanner pod Ready there is not the check: pods do not move back after a drain, so it would fail every time.

```bash
# The device plugin re-registers after the reboot (timeout: 5 minutes)
kubectl wait --for=jsonpath='{.status.allocatable.gpu\.intel\.com/i915}'=2 node/<hostname> --timeout=300s

IMG=$(kubectl -n litellm get deploy litellm-llm-tool-guard -o jsonpath='{.spec.template.spec.containers[?(@.name=="llm-tool-guard")].image}')
kubectl run gpu-gate -n default --rm -i --restart=Never --image="${IMG:?}" --pod-running-timeout=3m --override-type=strategic \
  --overrides='{"spec":{"automountServiceAccountToken":false,"nodeSelector":{"kubernetes.io/hostname":"<hostname>"},"securityContext":{"runAsUser":1000,"runAsGroup":1000,"runAsNonRoot":true,"supplementalGroups":[44],"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"gpu-gate","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"resources":{"limits":{"gpu.intel.com/i915":"1"}}}]}}' \
  --command -- python3 -c 'import openvino as ov; c=ov.Core(); print("devices:", c.available_devices); print("GPU:", c.get_property("GPU","FULL_DEVICE_NAME"))'
```

The image comes from the live Deployment, so the gate follows Renovate bumps. The pod copies the scanner's user, groups, seccomp and capabilities, and requests one of the node's two GPU shares. Group 44 owns `/dev/dri/renderD*`: without it OpenVINO lists only `CPU`. `--override-type=strategic` is required: the default merge replaces `containers` and drops the image.

**Good:** `devices:` includes `'GPU'`, a `GPU: Intel(R) ... Graphics` line follows, and the pod is deleted. Anything else (allocatable never reaches 2, no `GPU` in `devices:`, `terminated (Error)`, a timeout) fails the gate. After an upgrade, report WORKER UPGRADE BLOCKED ([templates.md](templates.md)) with the failing output, name the GPU gate as the reason, and stop before the next ms-01; in Phase 1 it is PRE-UPGRADE BLOCKED. No CPU fallback.

## Step 4.5: Wait for Ceph recovery

```bash
# Poll until Ceph is ready as defined in Step 4.1 (timeout: 30 minutes)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
```

Expect `HEALTH_WARN` for a few minutes after the reboot, including the NOOUT flag after PGs are clean. Stale heartbeat warnings (`OSD_SLOW_PING_TIME_*`) decay on their own: judge safety by data state, not the `HEALTH_OK` string, and prefer waiting over restarting an OSD. The recovery timeline, the heartbeat checks and the only case that warrants an OSD restart are in [ceph-recovery.md](ceph-recovery.md).

## Step 4.6: Post progress to issue

Post progress to the issue after each worker, including Ceph recovery time, with node names only.
