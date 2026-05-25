# Rook-Ceph Storage Runbook

## Overview

Rook-Ceph provides distributed storage services for Kubernetes workloads, including block storage (RBD), shared filesystem storage (CephFS), and object storage (RGW).

## Current Version

Chart versions are managed by Renovate and Flux. Check the release files for current pinned versions:

- **Operator**: `cluster/apps/rook-ceph/rook-ceph-operator/app/release.yaml`
- **Cluster**: `cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml`

## Prerequisites

- Storage nodes must be available with NVMe devices meeting the regular expression in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml)
- Velero schedules capture the `rook-ceph` namespace and required secrets for backup operations

## Operation

### Preconditions

- Target disks visible and unused:

  ```bash
  talosctl --nodes <node-ip> ls /dev/disk/by-id | grep KINGSTON
  ```

### Day-2 Operations and Capacity Management

1. **Add storage nodes** -- Label new nodes and verify devices:

   ```bash
   kubectl label node <hostname> node-role.kubernetes.io/worker=
   talosctl --nodes <node-ip> ls /dev/disk/by-id
   ```

   Extend the `devicePathFilter` in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml) and commit.

2. **Add or replace OSD devices** -- Use orchestrator commands in the toolbox:

   ```bash
   ceph orch device ls
   ceph orch daemon add osd <host>:<device-path>
   ceph osd df
   ```

3. **Remove OSD for maintenance** -- Drain and remove the daemon:

   ```bash
   ceph osd out <id>
   ceph orch daemon stop osd.<id>
   ceph orch daemon rm osd.<id> --force
   ```

   Recreate after hardware service using the add flow.

4. **Pool tuning** -- Apply changes and persist in Git:

   ```bash
   ceph osd pool set <pool> size 3
   ceph osd pool application enable csi-rbd-nvme rbd
   ```

5. **Block image maintenance** -- Flatten cloned RBD images to remove dependency on parent snapshots:

   ```bash
   # List children of a snapshot to see what needs flattening
   rbd list <pool>/<image>@<snapshot>

   # Flatten an image to make it independent
   rbd flatten <pool>/<image>

   # After flattening, you can remove the parent snapshot if no longer needed
   rbd snap unprotect <pool>/<image>@<snapshot>
   rbd snap rm <pool>/<image>@<snapshot>
   ```

6. **Clearing health warnings** -- Clear persistent warnings after recovery

   ```bash
   kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
   ceph crash archive-all
   ```

### Disaster Recovery and Restore Path

1. Restore namespace objects with Velero after etcd stability is confirmed:

   ```bash
   velero restore create rook-ceph-restore-$(date +%Y%m%d%H%M) \
     --from-backup rook-ceph-scheduled-latest \
     --include-namespaces rook-ceph \
     --preserve-nodeports \
     --wait
   ```

2. Recover Ceph data from snapshots when needed:

   ```bash
   rbd snap ls <pool>/<image>
   rbd snap rollback <pool>/<image>@<snapshot>
   ```

3. Validate daemon health post-restore:

   ```bash
   ceph orch ps --daemon-type mon,osd,mgr
   ceph health
   ```

### Escalation

- Engage storage on-call with recent `ceph status`, `kubectl -n rook-ceph get events`, and the Flux commit SHA.
- Capture `ceph crash ls` and `ceph crash info <id>` outputs prior to external escalation.

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

### OSD down or out unexpectedly

1. List failing daemons:

   ```bash
   ceph osd tree | grep down
   ```

2. Review crash data:

   ```bash
   ceph crash ls
   ceph crash info <crash-id>
   ```

3. Restart or replace the daemon:

   ```bash
   ceph orch daemon restart osd.<id>
   ```

   If hardware failed, follow the removal and replacement steps in Day-2 operations.

### PersistentVolumeClaims stuck in `Pending`

1. Inspect provisioner logs:

   ```bash
   kubectl -n rook-ceph logs deploy/rook-ceph-csi-rbd-provisioner -c csi-provisioner
   ```

2. Confirm pool capacity:

   ```bash
   ceph df
   ceph osd pool stats <pool>
   ```

3. Ensure node plugins can map RBD devices; restart relevant DaemonSet pods if mount errors persist.

### Velero restore conflicts or failures

1. Retry with `--restore-volumes=false` when PVC data remains intact but CRDs need reseeding.

## Object Storage (RGW)

Ceph Object Storage provides S3-compatible object storage via the RADOS Gateway (RGW). Two object stores are deployed:

<!-- markdownlint-disable MD013 -->

| Store     | Type                | Port | Use Case                                    |
| --------- | ------------------- | ---- | ------------------------------------------- |
| `fast`    | 3-way replicated    | 8080 | High-durability workloads, default          |
| `fast-ec` | Erasure-coded (2+1) | 8081 | Capacity-efficient storage (~1.5x overhead) |

<!-- markdownlint-enable MD013 -->

### Storage Classes

Four StorageClasses enable declarative bucket provisioning via `ObjectBucketClaim`:

| StorageClass            | Store   | Reclaim Policy |
| ----------------------- | ------- | -------------- |
| `ceph-bucket`           | fast    | Retain         |
| `ceph-bucket-delete`    | fast    | Delete         |
| `ceph-bucket-ec`        | fast-ec | Retain         |
| `ceph-bucket-ec-delete` | fast-ec | Delete         |

### Internal Users

Rook automatically creates internal users for RGW management:

- **`dashboard-admin`** -- Created per-realm for Ceph Dashboard integration with RGW
- **`rgw-admin-ops-user`** -- Created on-demand when ObjectBucketClaim or CephBucketNotification resources are deployed

### Creating Buckets with ObjectBucketClaim

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

This creates:

- An S3 bucket in the `fast` object store
- A ConfigMap `my-bucket` with bucket info (BUCKET_NAME, BUCKET_HOST, BUCKET_PORT)
- A Secret `my-bucket` with credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)

### Configuration Notes

- **`preservePoolsOnDelete: false`** -- Pools are deleted when CephObjectStore is removed. GitOps provides protection; manual deletion requires explicit pool removal.
- **Dashboard integration** -- SSO config and zone system_key setup handled by init container in toolbox deployment (see `release.yaml` postRenderers).
- **Default realm** -- `fast` is set as the global default realm/zonegroup/zone for dashboard display.

## Grafana Dashboard Integration

The Ceph Dashboard embeds Grafana panels for metrics visualization. This requires specific configuration in both Grafana and Ceph.

### Requirements

1. **Dashboard1 datasource** -- The Ceph Dashboard hardcodes `var-datasource=Dashboard1` in iframe URLs. A Grafana datasource named exactly "Dashboard1" must exist pointing to Prometheus/VictoriaMetrics.

2. **Official ceph-mixin dashboards** -- The Ceph Dashboard expects dashboards with specific UIDs from the [ceph-mixin](https://github.com/ceph/ceph/tree/main/monitoring/ceph-mixin/dashboards_out):

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

3. **Grafana embedding** -- Enable iframe embedding in Grafana config:

   ```yaml
   grafana.ini:
     security:
       allow_embedding: true
       cookie_samesite: disabled
   ```

### Configuration (Done via Init Container)

The toolbox deployment includes an init container that configures monitoring endpoints:

```bash
ceph dashboard set-alertmanager-api-host 'http://vmalertmanager-victoria-metrics-k8s-stack.observability.svc.cluster.local:9093'
ceph dashboard set-grafana-api-url 'http://victoria-metrics-k8s-stack-grafana.observability.svc.cluster.local:80'
ceph dashboard set-grafana-frontend-api-url 'https://grafana.lan.${EXTERNAL_DOMAIN}'
ceph dashboard set-grafana-api-ssl-verify false
ceph dashboard set-alertmanager-api-ssl-verify false
```

The `prometheusEndpoint` is configured via the CephCluster CRD in `values.yaml`:

```yaml
cephClusterSpec:
  dashboard:
    prometheusEndpoint: http://vmsingle-victoria-metrics-k8s-stack.observability.svc.cluster.local:8428
    prometheusEndpointSSLVerify: false
```

### Dashboard Locations

- **Custom dashboards** -- `cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/`
- **Dashboard ConfigMaps** -- `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml`
- **Dashboard1 datasource** -- `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml` under `defaultDatasources.extra`

## References

- [Rook Ceph documentation](https://rook.io/docs/rook/latest/)
- [Ceph Dashboard Grafana integration source](https://github.com/ceph/ceph/blob/main/src/pybind/mgr/dashboard/frontend/src/app/shared/components/grafana/grafana.component.ts)
- [Ceph mixin dashboards](https://github.com/ceph/ceph/tree/main/monitoring/ceph-mixin/dashboards_out)
