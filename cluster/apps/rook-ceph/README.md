# Rook-Ceph Storage Runbook

## Purpose and Scope

This runbook documents how operators deploy, maintain, and recover the
Rook-Ceph storage stack that lives under [`cluster/apps/rook-ceph`](.). It
aligns with the repository-wide operational standards described in
[`README.md`](../../README.md#runbook-standards) and centers on daily storage
lifecycle management, incident response, and backup integration.

## Architecture Overview

- **Rook-Ceph Operator** – Reconciled through
  [`rook-ceph-operator/ks.yaml`](rook-ceph-operator/ks.yaml) and
  [`rook-ceph-operator/app/release.yaml`](rook-ceph-operator/app/release.yaml);
  installs CRDs, operators, and CSI sidecars.
- **Ceph Cluster Helm release** – Defined in
  [`rook-ceph-cluster/ks.yaml`](rook-ceph-cluster/ks.yaml) and
  [`rook-ceph-cluster/app/release.yaml`](rook-ceph-cluster/app/release.yaml);
  renders the `CephCluster` CR via
  [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml).
- **Storage overlays** – Pools and storage classes are organized beneath
  [`rook-ceph-cluster/storage`](rook-ceph-cluster/storage) with block, object,
  and filesystem overlays.
- **Toolbox pod** – Enabled in the Helm values and reachable with
  `task rook-ceph:tools` for direct `ceph` CLI administration.
- **Talos worker nodes** – NVMe devices filtered with deterministic patterns to
  avoid provisioning on unintended hardware.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                                            | Description                                                                              |
| ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [`cluster/apps/rook-ceph/kustomization.yaml`](kustomization.yaml)                               | Root Kustomize entry that wires the namespace, operator, and cluster overlays.           |
| [`cluster/apps/rook-ceph/namespace.yaml`](namespace.yaml)                                       | Namespace definition with pod-security labels suitable for privileged storage workloads. |
| [`cluster/apps/rook-ceph/rook-ceph-operator`](rook-ceph-operator)                               | Flux Kustomization and HelmRelease for the operator deployment.                          |
| [`cluster/apps/rook-ceph/rook-ceph-cluster`](rook-ceph-cluster)                                 | Flux Kustomization and HelmRelease for the Ceph cluster resources.                       |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml) | Helm values configuring Ceph networking, encryption, resources, devices, and monitoring. |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage`](rook-ceph-cluster/storage)                 | Storage overlays defining pools, storage classes, and snapshot classes.                  |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage/block`](rook-ceph-cluster/storage/block)     | RBD block pools, `StorageClass`, and `VolumeSnapshotClass` definitions.                  |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage/object`](rook-ceph-cluster/storage/object)   | Object store and user manifests for Ceph RGW (enabled as required).                      |
| [`.taskfiles/rook-ceph/tasks.yaml`](../../.taskfiles/rook-ceph/tasks.yaml)                      | Task runner target that opens an interactive shell in the toolbox deployment.            |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Operate from the devcontainer or ensure `kubectl`, `flux`, `talosctl`, `velero`,
  `yq`, and `task` are installed with matching versions.
- Possess the Age identity material for decrypting SOPS secrets and the Talos
  `talosconfig` for node inspections.
- Verify the workstation reaches the Kubernetes API, Talos control plane, and
  the Ceph dashboard ingress when exposed.
- Confirm NVMe devices on target nodes meet the regular expression in
  [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml).
- Ensure Velero schedules capture the `rook-ceph` namespace and required secrets.

## Operational Runbook

### Summary

Bootstrap and operate the Rook-Ceph storage fabric to provide resilient block
and object storage services. Maintain OSD and pool health, perform routine
capacity operations, and execute restore procedures with Velero and Ceph
snapshots during incidents.

### Preconditions

- Clean working tree or current feature branch prepared for promotion.
- Flux control plane healthy:

  ```bash
  flux check
  flux get kustomizations -n flux-system
  ```

- Talos control plane members stable:

  ```bash
  talosctl --nodes <ip-list> health
  ```

- No maintenance holds on worker nodes that host Ceph OSDs:

  ```bash
  kubectl get node -l node-role.kubernetes.io/worker
  ```

- Target disks visible and unused:

  ```bash
  talosctl --nodes <node-ip> ls /dev/disk/by-id | grep KINGSTON
  ```

### Procedure

#### Phase 1 – Provision or Re-provision Rook-Ceph

1. Reconcile operator components:

   ```bash
   flux reconcile kustomization rook-ceph-operator --with-source
   kubectl -n rook-ceph get pods
   ```

2. Reconcile cluster and storage overlays:

   ```bash
   flux reconcile kustomization rook-ceph-cluster --with-source
   flux reconcile kustomization rook-ceph-cluster-storage --with-source
   ```

3. Validate CephCluster status:

   ```bash
   kubectl -n rook-ceph get cephcluster rook-ceph -o yaml | yq '.status.ceph.health'
   kubectl -n rook-ceph get cephblockpool
   ```

4. Enter the toolbox and inspect health:

   ```bash
   task rook-ceph:tools
   # inside toolbox
   ceph status
   ceph osd tree
   ```

5. Confirm CSI registration:

   ```bash
   kubectl get csidrivers | grep rook
   kubectl get storageclasses | grep -E 'rook-(ceph|rbd)'
   ```

6. Monitor until `ceph status` reports `HEALTH_OK` or expected transient warnings.

#### Phase 2 – Day-2 Operations and Capacity Management

1. **Add storage nodes** – Label new nodes and verify devices:

   ```bash
   kubectl label node <hostname> node-role.kubernetes.io/worker=
   talosctl --nodes <node-ip> ls /dev/disk/by-id
   ```

   Extend the `devicePathFilter` in
   [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml),
   commit, and reconcile:

   ```bash
   flux reconcile kustomization rook-ceph-cluster --with-source
   ```

2. **Add or replace OSD devices** – Use orchestrator commands in the toolbox:

   ```bash
   ceph orch device ls
   ceph orch daemon add osd <host>:<device-path>
   ceph osd df
   ```

3. **Remove OSD for maintenance** – Drain and remove the daemon:

   ```bash
   ceph osd out <id>
   ceph orch daemon stop osd.<id>
   ceph orch daemon rm osd.<id> --force
   ```

   Recreate after hardware service using the add flow.

4. **Pool tuning** – Apply changes and persist in Git:

   ```bash
   ceph osd pool set <pool> size 3
   ceph osd pool application enable csi-rbd-nvme rbd
   ```

5. **Routine health checks** – Schedule or run manually:

   ```bash
   kubectl -n rook-ceph get cephcluster rook-ceph
   ceph health detail
   ceph pg stat
   ```

#### Phase 3 – Disaster Recovery and Restore Path

1. Assess overall impact:

   ```bash
   kubectl -n rook-ceph get cephcluster rook-ceph
   ceph status
   talosctl --nodes <control-plane> etcd status
   ```

2. Restore namespace objects with Velero after etcd stability is confirmed:

   ```bash
   velero restore create rook-ceph-restore-$(date +%Y%m%d%H%M) \
     --from-backup rook-ceph-scheduled-latest \
     --include-namespaces rook-ceph \
     --preserve-nodeports \
     --wait
   velero restore describe rook-ceph-restore-$(date +%Y%m%d%H%M)
   ```

3. Recover Ceph data from snapshots when needed:

   ```bash
   rbd snap ls <pool>/<image>
   rbd snap rollback <pool>/<image>@<snapshot>
   ```

4. Re-bootstrap Ceph if the CR was removed:

   ```bash
   kubectl delete cephcluster rook-ceph -n rook-ceph --ignore-not-found
   flux reconcile kustomization rook-ceph-cluster --with-source
   ```

5. Validate daemon health post-restore:

   ```bash
   ceph orch ps --daemon-type mon,osd,mgr
   ceph health
   kubectl get pvc -A | grep rook
   ```

6. Coordinate Talos etcd recovery using
   [`talos/docs/machine-lifecycle.md`](../../talos/docs/machine-lifecycle.md) if
   the control plane was rebuilt.

#### Phase 4 – Velero Backup Integration

1. Capture ad hoc backups:

   ```bash
   velero backup create rook-ceph-config-$(date +%Y%m%d) \
     --include-namespaces rook-ceph \
     --ttl 240h
   ```

2. Monitor backup status:

   ```bash
   velero backup get | grep rook-ceph
   ```

3. Ensure Ceph credentials and secrets reside in Velero snapshots for restores.
4. Align retention and storage targets with the forthcoming Velero runbook:
   [`cluster/apps/velero/README.md`](../velero/README.md) _(pending)_.

### Validation

- `kubectl -n rook-ceph get cephcluster rook-ceph` reports
  `status.ceph.health=HEALTH_OK`.
- `ceph status` and `ceph osd tree` show monitors and OSDs in `up/in` state.
- `flux reconcile kustomization rook-ceph-cluster --with-source` completes with
  healthy checks.
- `velero restore describe <name>` reports `Phase: Completed` without warnings.

### Troubleshooting Guidance

Refer to the dedicated [Troubleshooting](#troubleshooting) section after
performing the above validation.

### Escalation

- Engage storage on-call with recent `ceph status`, `kubectl -n rook-ceph get
events`, and the Flux commit SHA.
- Loop in Talos owners if node or etcd instability contributes to storage
  issues.
- Coordinate with backup owners before manipulating Velero backup objects.
- Capture `ceph crash ls` and `ceph crash info <id>` outputs prior to external
  escalation.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Tooling / Command                                                           | Purpose                                                              |
| --------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `task rook-ceph:tools`                                                      | Opens the toolbox pod for interactive `ceph` commands.               |
| `kubectl -n rook-ceph get cephcluster rook-ceph`                            | Confirms CephCluster status and operator reconciliation.             |
| `flux reconcile kustomization rook-ceph-cluster --with-source`              | Forces Helm release sync and re-runs Flux health checks.             |
| `ceph status`                                                               | Provides cluster health, quorum, and placement group metrics.        |
| `ceph osd tree`                                                             | Audits OSD distribution and reveals `down` or `out` daemons.         |
| `velero restore create --from-backup <name> --wait`                         | Validates Velero restore workflow for namespace resources.           |
| `kubectl get pvc -A --field-selector spec.storageClassName=rook-ceph-block` | Confirms workloads bind to the intended storage class after changes. |

<!-- markdownlint-enable MD013 -->

## Troubleshooting

### Ceph reports `HEALTH_WARN` or `HEALTH_ERR`

1. Inspect detailed health:

   ```bash
   ceph health detail
   ```

2. Identify failing services:

   ```bash
   ceph orch ps --daemon-type mon,mgr,osd
   ```

3. Address the root cause (resolve backfill delays, restart pods, fix network
   partitions) and continue monitoring until `HEALTH_OK` returns.

### OSD down or out unexpectedly

1. List failing daemons:

   ```bash
   ceph osd tree | grep down
   ```

2. Check pod status:

   ```bash
   kubectl -n rook-ceph get pods -l app=rook-ceph-osd
   ```

3. Review crash data:

   ```bash
   ceph crash ls
   ceph crash info <crash-id>
   ```

4. Restart or replace the daemon:

   ```bash
   ceph orch daemon restart osd.<id>
   ```

   If hardware failed, follow the removal and replacement steps in the
   Day-2 operations phase.

### PersistentVolumeClaims stuck in `Pending`

1. Verify storage classes exist:

   ```bash
   kubectl get sc | grep rook
   ```

2. Inspect provisioner logs:

   ```bash
   kubectl -n rook-ceph logs deploy/rook-ceph-csi-rbd-provisioner -c csi-provisioner
   ```

3. Confirm pool capacity:

   ```bash
   ceph df
   ceph osd pool stats <pool>
   ```

4. Ensure node plugins can map RBD devices; restart relevant DaemonSet pods if
   mount errors persist.

### Velero restore conflicts or failures

1. Describe restore for warnings:

   ```bash
   velero restore describe <restore-name>
   velero restore logs <restore-name>
   ```

2. Remove stale resources before re-running restore:

   ```bash
   kubectl delete cephcluster rook-ceph -n rook-ceph --wait=false
   ```

3. Retry with `--restore-volumes=false` when PVC data remains intact but CRDs
   need reseeding.
4. Reconcile operator CRDs to ensure correct versions:

   ```bash
   flux reconcile kustomization rook-ceph-operator --with-source
   ```

## References and Cross-links

- Repository runbook standards:
  [`README.md`](../../README.md#runbook-standards)
- Application deployment overview:
  [`cluster/apps/README.md`](../README.md)
- Flux control plane operations:
  [`cluster/flux/README.md`](../../flux/README.md)
- Custom resource lifecycle guidance:
  [`cluster/crds/README.md`](../../crds/README.md)
- Talos machine lifecycle and etcd recovery:
  [`talos/docs/machine-lifecycle.md`](../../talos/docs/machine-lifecycle.md)
- Velero backup runbook (pending authoring):
  [`cluster/apps/velero/README.md`](../velero/README.md) _(pending)_
- Rook documentation: <https://rook.io/docs/rook/latest/>
- Ceph upstream operations guide: <https://docs.ceph.com/en/latest/>

## Changelog

- _TBD — record future updates in the format `yyyy-mm-dd · short summary ·
PR/commit reference`._
