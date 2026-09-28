# Rook-Ceph Storage

## Overview

Rook-Ceph provides all persistent storage: RBD block (replicated and 2+1 erasure-coded, with encrypted variants), CephFS, and S3-compatible object storage via RGW. It runs on the three MS-01 workers, one encrypted NVMe OSD each, with replication over a dedicated Thunderbolt ring. Component READMEs:

- [rook-ceph-cluster](rook-ceph-cluster/README.md) - Thunderbolt ring network and its failure modes
- [rook-ceph-csi-drivers](rook-ceph-csi-drivers/README.md) - ceph-csi-operator Driver CRs and their workarounds

Ceph commands below run in the toolbox: `task rook-ceph:tools`.

## Prerequisites

- OSD devices are selected by `/dev/disk/by-id` path in `devicePathFilter` in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml). A disk not in the filter is never used.
- Ring network, link aliases and fallback routes are Talos config under `talos/patches/worker/` and `talos/patches/node/ms-01-*/`.

## Operation

> **No `ceph orch` in this cluster.** The `rook` mgr module is disabled under `cephClusterSpec.mgr.modules` in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml), matching the upstream chart default (it leaks memory or crashes the mgr on current Ceph releases), so there is no orchestrator backend and `ceph orch ...` returns `Error ENOENT: Module not found`. Daemon lifecycle
> is driven by the operator from the CephCluster CR instead. The Ceph Dashboard's Physical Disks, Services and Upgrade pages show "Orchestrator is not available" for the same reason.

### Adding or replacing an OSD

OSD creation is declarative. Find the device's `by-id` path, add it to `devicePathFilter`, and commit; the operator runs the OSD prepare job on the next reconcile.

```bash
# Devices Ceph already knows about, with host and OSD mapping
ceph device ls
# Everything present on the node, including unclaimed disks
talosctl --nodes <node-ip> ls /dev/disk/by-id
```

### Removing an OSD

Scaling the OSD Deployment is the Rook equivalent of `ceph orch daemon stop`.

> `ceph osd purge` is irreversible. Confirm every PG is `active+clean` and that the remaining OSDs have capacity for the data first. Remove one OSD at a time.

```bash
ceph osd out <id>
# Wait until backfill finishes and all PGs report active+clean
ceph status
kubectl -n rook-ceph scale deploy/rook-ceph-osd-<id> --replicas=0
ceph osd purge <id> --yes-i-really-mean-it
kubectl -n rook-ceph delete deploy/rook-ceph-osd-<id>
```

Drop the retired device from `devicePathFilter` in the same commit, otherwise the operator recreates the OSD on the next reconcile. The replacement may get a different OSD ID.

### Restore

Velero backs up the `rook-ceph` namespace objects with the rest of the cluster (`spruyt-labs-cluster-backup-*`); the restore procedure is in [`docs/disaster-recovery.md`](../../../docs/disaster-recovery.md). Pool data itself is not in Velero - only PVCs that opt in via the `velero.io/backup-volumes` label are copied out (see [velero](../velero/velero/README.md)).

## Troubleshooting

### CephX key rotation (`aes` / `aes256k`)

Ceph v20.2.4 fixed CVE-2025-30156 by adding a new CephX key type, `aes256k`, plus six `AUTH_INSECURE_*` health checks that fire while keys are still `aes`. Configuration lives under `cephClusterSpec.security.cephx` and `cephClusterSpec.healthCheck.muteHealthWarning` in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml).

Current state:

| Key set                                              | Type      | Notes                                   |
| ---------------------------------------------------- | --------- | --------------------------------------- |
| Daemons (`mon`, `mgr`, `osd`, `mds`, `rgw`, `crash`) | `aes256k` | `keyRotationPolicy: KeyGeneration`      |
| `client.rbd-mirror-peer`                             | `aes256k` | No mirroring configured, safe to rotate |
| CSI clients (`csi-rbd-*`, `csi-cephfs-*`)            | `aes`     | Pinned - see kernel gate below          |

**Why CSI stays on `aes`:** upstream kernel support for `aes256k` begins in Linux 7.0. The nodes run kernel 6.18.x and this cluster uses the _kernel_ mounter for both RBD and CephFS, so rotating CSI keys to `aes256k` would strand every kernel-mounted PVC (#2558). Do not set `allowedCiphers: [aes256k]` either - it would reject the still-`aes` CSI keys.

Because of that, `AUTH_INSECURE_CLIENT_KEY_TYPE`, `AUTH_INSECURE_KEYS_ALLOWED` and `AUTH_INSECURE_KEYS_CREATABLE` remain and are muted declaratively via `healthCheck.muteHealthWarning` (Rook re-applies the mute on reconcile; `ceph health mute` has a TTL and would silently lapse).

**Why `daemon.keyType` stays unset:** Rook's default preferred cipher is already `aes256k`, so pinning `daemon.keyType` buys nothing - and it makes Rook pass `--mon-auth-emergency-allowed-ciphers=aes,aes256k` to the mons, which raises a permanent `AUTH_EMERGENCY_CIPHERS_SET` warning. Upstream treats that field as a bootstrap/recovery workaround only.

**Rotating daemon keys again** - increment `keyGeneration` under `security.cephx.daemon` and commit. Rook restarts daemons one at a time; expect several minutes and transient PG peering.

The generation counter is tracked _per entity_, not cluster-wide, and daemons created under earlier Ceph releases may already sit above 0 from automatic rotations during upgrades. The MDS and OSD rotation paths also ignore `keyType` entirely (`ignoreKeyType=true` upstream), so a generation bump is the only lever that moves them. Set `keyGeneration` strictly higher than the highest value already
recorded:

```bash
# CephCluster-level (mon, mgr, exporter, crash, ...)
kubectl -n rook-ceph get cephcluster rook-ceph -o json | jq '.status.cephx'
# Child CRs track their own generation
kubectl -n rook-ceph get cephfilesystem,cephobjectstore -o json | jq '.items[] | {name: .metadata.name, cephx: .status.cephx}'
# OSDs store it in a pod-template annotation
kubectl -n rook-ceph get deploy -l app=rook-ceph-osd \
  -o custom-columns=NAME:.metadata.name,CEPHX:'.spec.template.metadata.annotations.cephx-status'
```

If the toolbox errors on the admin keyring after rotation, restart it:

```bash
kubectl -n rook-ceph rollout restart deploy/rook-ceph-tools
```

**Emergency escape** - if daemons cannot authenticate after a rotation, widen the ciphers and force the old type, wait for mon pods to show `--mon-auth-emergency-allowed-ciphers`, confirm recovery, then drop the `daemon.keyType` override:

```yaml
security:
  cephx:
    allowedCiphers: [aes, aes256k]
    daemon:
      keyType: aes # workaround only
```

**Unmute procedure** (once every node runs kernel >= 7.0):

1. Confirm the kernel on every node:

   ```bash
   kubectl get nodes -o custom-columns=NAME:.metadata.name,KERNEL:.status.nodeInfo.kernelVersion
   ```

2. Set `security.cephx.csi` to `keyRotationPolicy: KeyGeneration`, `keyGeneration: 1`, `keepPriorKeyCountMax: 1`, `keyType: aes256k`.

3. Wait for `status.cephx.csi.keyGeneration` to advance, then cordon/drain/uncordon each node in turn so pods remount with the new key.

4. Set `keepPriorKeyCountMax: 0` and add `allowedCiphers: [aes256k]`.

5. Flip every `muteHealthWarning` entry to `policy: unmute`.

### Toolbox init container changes do not take effect

The Ceph Dashboard SSO, RGW realm and Grafana/Alertmanager settings are applied by the `sso-config` init container patched into `rook-ceph-tools` via `postRenderers` in `rook-ceph-cluster/app/release.yaml`. Its image must match `cephImage.tag` in `values.yaml`. After changing its script, delete the toolbox pod so the init container runs again.

## Object Storage (RGW)

Two object stores, each exposed through `ObjectBucketClaim` StorageClasses:

| Store     | Data pool           | StorageClasses                                     |
| --------- | ------------------- | -------------------------------------------------- |
| `fast`    | 3-way replicated    | `ceph-bucket` (Retain), `ceph-bucket-delete`       |
| `fast-ec` | Erasure-coded (2+1) | `ceph-bucket-ec` (Retain), `ceph-bucket-ec-delete` |

An `ObjectBucketClaim` in an app namespace creates the bucket plus a ConfigMap (`BUCKET_NAME`, `BUCKET_HOST`, `BUCKET_PORT`) and a Secret (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), both named after the claim:

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: my-bucket
  namespace: my-app
spec:
  storageClassName: ceph-bucket
  generateBucketName: my-bucket
```

Notes:

- **`preservePoolsOnDelete: false`** - deleting a CephObjectStore deletes its pools and all data. Git is the only protection.
- **Internal RGW users** - Rook creates `dashboard-admin` per realm for the Dashboard, and `rgw-admin-ops-user` when an ObjectBucketClaim or CephBucketNotification first appears. Do not delete them.
- **Default realm** - the toolbox init container sets `fast` as the default realm/zonegroup/zone and configures each zone's `system_key`, which the Dashboard needs to show RGW status.

## Grafana Dashboard Integration

The Ceph Dashboard embeds Grafana panels, which needs matching configuration on both sides.

### Requirements

1. **`Dashboard1` datasource** - the Ceph Dashboard hardcodes `var-datasource=Dashboard1` in its iframe URLs. A Grafana datasource named exactly `Dashboard1` must point at VictoriaMetrics (`defaultDatasources.extra` in `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml`).

2. **Official ceph-mixin dashboards** - the Ceph Dashboard looks dashboards up by fixed UID, so the [ceph-mixin](https://github.com/ceph/ceph/tree/main/monitoring/ceph-mixin/dashboards_out) JSON must be loaded unmodified:

   | Dashboard                  | UID                 | Used By                 |
   | -------------------------- | ------------------- | ----------------------- |
   | ceph-cluster.json          | `ceph-cluster`      | Cluster overview        |
   | hosts-overview.json        | `-uVQuofik`         | Hosts list              |
   | osds-overview.json         | `lo02I1Aiz`         | OSD list                |
   | pool-overview.json         | `41FrpeUiz`         | Pool overview           |
   | pool-detail.json           | `jE2s4dzik`         | Pool details            |
   | osd-device-details.json    | `CrAHE0iZz`         | OSD device details      |
   | rbd-overview.json          | `t2bQAeXGz`         | RBD overview            |
   | rbd-details.json           | `YhCYGcuZz`         | RBD details             |
   | radosgw-overview.json      | `WAkugZpiz`         | RGW overall performance |
   | radosgw-sync-overview.json | `rgw-sync-overview` | RGW sync performance    |
   | radosgw-detail.json        | `x5ARzZtmk`         | RGW instance details    |
   | cephfsdashboard.json       | `MUsmxkziz`         | CephFS overview         |

   The mixin's `node-exporter.json` is not loaded: it shares UID `rYdddlPWk` with the VM stack's node-exporter dashboard, which the Ceph iframes work with.

3. **Grafana embedding** - `security.allow_embedding: true` and `cookie_samesite: disabled` in the Grafana config.

### Where it is configured

- Grafana/Alertmanager URLs (`ceph dashboard set-grafana-api-url`, `set-alertmanager-api-host`, ...) are set by the toolbox init container.
- `prometheusEndpoint` is set in `cephClusterSpec.dashboard` in `values.yaml`.
- Dashboards are ConfigMaps generated in `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml` from JSON in `app/dashboards/`.

## References

- [Rook Ceph documentation](https://rook.io/docs/rook/latest/)
- [Ceph Dashboard Grafana integration source](https://github.com/ceph/ceph/blob/main/src/pybind/mgr/dashboard/frontend/src/app/shared/components/grafana/grafana.component.ts)
