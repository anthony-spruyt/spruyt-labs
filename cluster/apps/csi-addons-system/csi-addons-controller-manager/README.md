# CSI Addons Controller Manager - RBD Reclaim Space and Network Fencing

## Overview

Runs the scheduled `ReclaimSpace` (fstrim/sparsify) jobs for Ceph RBD PVCs and backs the `NetworkFenceClass` in `rook-ceph-cluster`. Deployed from plain upstream manifests rather than a chart.

## Operations

### Reclaim schedule lives on the StorageClass

The schedule is the `reclaimspace.csiaddons.openshift.io/schedule` annotation on each RBD StorageClass in `rook-ceph/rook-ceph-cluster/storage/block/storage-classes.yaml`. `schedule-precedence: storageclass` in `app/csi-addons-config.yaml` makes the controller re-read it on every reconcile; under the default precedence the schedule is copied onto each PVC once and later StorageClass edits never
reach existing volumes. The controller spreads jobs itself (UID-hashed offset inside `cronjob-stagger-window`), so keep one base time for all classes rather than hand-staggering them.

Every key in `csi-addons-config` is set explicitly on purpose: the controller hard-errors on unknown keys, so a typo crash-loops it.

### Daily controller restart (workaround)

`app/restart-cronjob.yaml` rolls the controller at 18:45, before the 19:00 reclaim window. After a sidecar rollout the controller keeps dialling the old sidecar address while every `CSIAddonsNode` still reports `Connected`, so reclaim jobs fail with dial timeouts. Status is not a usable health signal here. Upgrading to v0.15 did not fix it (#2624). Remove the CronJob, its RBAC and its egress CNP
together once upstream invalidates pooled connections on endpoint change.

### CRDs

Talos seeds the CRDs at bootstrap (`talos/patches/control-plane/07-extra-manifests.yaml`); after that the `csi-addons-crds` Kustomization owns them from the `csi-addons-gitrepo` source. Keep both tags in lockstep - Renovate does this.

## Troubleshooting

1. **Controller cannot reach the sidecar on its own node**
   - **Cause**: Cilium labels the local node `reserved:host` and every other node `reserved:remote-node`. An egress rule for the hostNetwork sidecar ports that lists only `remote-node` drops traffic to the co-located sidecar.
   - **Fix**: Keep both entities in the egress rule in `app/network-policies.yaml`.

## References

- [kubernetes-csi-addons](https://github.com/csi-addons/kubernetes-csi-addons)
