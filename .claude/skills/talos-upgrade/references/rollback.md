# Rollback Procedures

## Control Plane Rollback

If a control plane upgrade fails:

```bash
# Attempt downgrade to previous version
talosctl upgrade \
  --nodes <failed-node-ip> \
  --endpoints <working-cp-ip> \
  --image factory.talos.dev/metal-installer-secureboot/<schematic>:<previous-version>
```

**If etcd quorum is lost (< 2 healthy members):** stop and report ROLLBACK to the owner. Recovery wipes EPHEMERAL on the failed control planes and rolls the whole cluster back to the snapshot, so the owner runs it from `docs/disaster-recovery.md` ("Restore etcd (Quorum Lost)") with the Phase 2 snapshot. Do not run it yourself.

## Worker Rollback

If a worker upgrade fails (`<cp-node-ip>` is any control plane node IP, as in Step 4.3):

```bash
# Downgrade to previous version
talosctl upgrade \
  --nodes <failed-node-ip> \
  --endpoints <cp-node-ip> \
  --image factory.talos.dev/metal-installer-secureboot/<schematic>:<previous-version>
```

**If Ceph remains degraded after worker recovery:**

```bash
# Check OSD status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree

# Check for stuck recovery
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
```
