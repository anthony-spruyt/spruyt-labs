# Ceph Recovery After a Worker Reboot

Detail for Step 4.5 (waiting for Ceph, stale heartbeat warnings) and Step 4.5a (stale `Error` pods). "Ceph ready" is defined in Step 4.1 of the skill.

## Step 4.5: Ceph recovery timeline

**Ceph recovery timeline expectations:**

| Time After Reboot | Expected State                                                        |
| ----------------- | --------------------------------------------------------------------- |
| 0-60s             | HEALTH_WARN (OSDs rejoining)                                          |
| 60-120s           | HEALTH_WARN (peering, PGs recovering)                                 |
| 120-180s          | All PGs active+clean, but HEALTH_WARN may persist due to NOOUT flag   |
| 180-300s          | HEALTH_OK (NOOUT flag auto-clears ~60s after PGs are clean)           |
| 300s+             | HEALTH_OK expected; if still WARN, check for stale heartbeat warnings |

**Note:** Rook-Ceph sets a NOOUT flag on OSDs during planned disruptions to prevent unnecessary rebalancing. This flag auto-clears after the OSD rejoins, but adds ~60 seconds of HEALTH_WARN **after** all PGs are already active+clean. This is normal and does not indicate a problem.

## Step 4.5: Stale heartbeat warnings

**Stale OSD heartbeat warnings (`OSD_SLOW_PING_TIME_BACK` / `OSD_SLOW_PING_TIME_FRONT`):**

These are a **decaying exponential moving average** of ping times sampled while the node was rebooting. They DO self-clear. Observed in practice: a peak of ~7900 ms decayed steadily to under the 1000 ms warning threshold over roughly 11 minutes, clearing without any intervention.

**Judge safety by data state, not by the overall `HEALTH_OK` string.** If the only remaining warnings are `OSD_SLOW_PING_TIME_*`, the cluster is already fully safe:

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status | grep -E "health|osd:|mon:|pgs:|volumes"
# Data is safe when: all OSDs up and in, all PGs active+clean, mons in quorum
```

Poll and watch the millisecond value trend. If it is **decreasing**, just keep waiting — it will clear. Budget up to ~15 minutes for this alone, on top of data recovery.

Only restart the OSD if the value is genuinely **flat across several minutes** (not decreasing):

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail   # identify the OSD
kubectl -n rook-ceph delete pod -l ceph-osd-id=<osd-id>
kubectl -n rook-ceph wait pod -l ceph-osd-id=<osd-id> --for=condition=Ready --timeout=120s
```

Prefer waiting over restarting. Restarting the OSD triggers another round of peering and degraded PGs, which is more disruptive than the cosmetic warning it resolves.

## Step 4.5a: Stale `Error` pods after node reboots

After a node reboot you will see pods in `Error` state from the previous boot. These are **stale pod objects**, not real failures — Kubernetes garbage collects them within a few minutes.

Leave them for garbage collection rather than deleting them, and judge health from controllers rather than pod phase:

```bash
kubectl get deploy -A -o json | jq -r '.items[] | select((.status.readyReplicas // 0) < (.spec.replicas // 0)) | "\(.metadata.namespace)/\(.metadata.name) \(.status.readyReplicas // 0)/\(.spec.replicas)"'
kubectl get cluster -A -o json | jq -r '.items[] | select(.status.phase != "Cluster in healthy state") | "\(.metadata.namespace)/\(.metadata.name) \(.status.phase)"'
```

If every controller reports full ready replicas, the `Error` pods are leftovers. Allow a few minutes for workloads (especially CNPG clusters) to settle before declaring a problem.
