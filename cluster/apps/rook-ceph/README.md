# Rook-Ceph Storage Runbook

## Overview

Rook-Ceph provides distributed storage services for Kubernetes workloads, including block storage (RBD), shared filesystem storage (CephFS), and object storage (RGW). This runbook documents the GitOps layout, deployment workflow, and operations for maintaining Rook-Ceph in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Current Version

Chart versions are managed by Renovate and Flux. Check the release files for current pinned versions:

- **Operator**: `cluster/apps/rook-ceph/rook-ceph-operator/app/release.yaml`
- **Cluster**: `cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml`

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage storage clusters.
- Ensure the workstation can reach the Kubernetes API and that the `rook-ceph` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Storage nodes must be available with NVMe devices meeting the regular expression in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml).
- Verify Velero schedules capture the `rook-ceph` namespace and required secrets for backup operations.

## Operation

### Summary

Operate the Rook-Ceph storage fabric to provide resilient block and object storage services. Maintain OSD and pool health, perform routine capacity operations, and execute restore procedures with Velero and Ceph snapshots during incidents.

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

- Capture the current Helm release revisions for rollback reference:

  ```bash
  kubectl -n rook-ceph get helmrelease rook-ceph-operator -o yaml
  kubectl -n rook-ceph get helmrelease rook-ceph-cluster -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/rook-ceph/rook-ceph-operator/app/` and `cluster/apps/rook-ceph/rook-ceph-cluster/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr rook-ceph-operator --namespace rook-ceph
   flux diff hr rook-ceph-cluster --namespace rook-ceph
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomizations:

   ```bash
   flux reconcile kustomization rook-ceph-operator --with-source
   flux reconcile kustomization rook-ceph-cluster --with-source
   flux get kustomizations rook-ceph-operator -n flux-system
   flux get kustomizations rook-ceph-cluster -n flux-system
   ```

2. Confirm the Helm release upgrades succeeded:

   ```bash
   flux get helmrelease rook-ceph-operator -n rook-ceph
   flux get helmrelease rook-ceph-cluster -n rook-ceph
   ```

#### Phase 3 – Monitor Storage Operations

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n rook-ceph
   kubectl logs -n rook-ceph deployment/rook-ceph-operator
   kubectl logs -n rook-ceph deployment/rook-ceph-mgr
   ```

2. Check Ceph cluster status:

   ```bash
   kubectl -n rook-ceph get cephcluster rook-ceph
   kubectl -n rook-ceph get cephcluster rook-ceph -o yaml | yq '.status.ceph.health'
   ```

3. Enter the toolbox and inspect health:

   ```bash
   task rook-ceph:tools
   # inside toolbox
   ceph status
   ceph osd tree
   ceph health detail
   ```

4. Confirm CSI registration:

   ```bash
   kubectl get csidrivers | grep rook
   kubectl get storageclasses | grep -E 'rook-(ceph|rbd)'
   ```

5. Monitor until `ceph status` reports `HEALTH_OK` or expected transient warnings.

#### Phase 4 – Day-2 Operations and Capacity Management

1. **Add storage nodes** – Label new nodes and verify devices:

   ```bash
   kubectl label node <hostname> node-role.kubernetes.io/worker=
   talosctl --nodes <node-ip> ls /dev/disk/by-id
   ```

   Extend the `devicePathFilter` in [`rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml), commit, and reconcile:

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

6. **Block image maintenance** – Flatten cloned RBD images to remove dependency on parent snapshots during maintenance:

   ```bash
   # List children of a snapshot to see what needs flattening
   rbd list <pool>/<image>@<snapshot>

   # Flatten an image to make it independent
   rbd flatten <pool>/<image>

   # After flattening, you can remove the parent snapshot if no longer needed
   rbd snap unprotect <pool>/<image>@<snapshot>
   rbd snap rm <pool>/<image>@<snapshot>
   ```

#### Phase 5 – Disaster Recovery and Restore Path

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

6. Coordinate Talos etcd recovery if the control plane was rebuilt.

#### Phase 6 – Velero Backup Integration

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
4. Align retention and storage targets with the Velero runbook.

#### Phase 7 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization rook-ceph-operator -n flux-system
   flux suspend kustomization rook-ceph-cluster -n flux-system
   flux suspend helmrelease rook-ceph-operator -n rook-ceph
   flux suspend helmrelease rook-ceph-cluster -n rook-ceph
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization rook-ceph-operator -n flux-system
   flux resume kustomization rook-ceph-cluster -n flux-system
   flux resume helmrelease rook-ceph-operator -n rook-ceph
   flux resume helmrelease rook-ceph-cluster -n rook-ceph
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n rook-ceph scale deploy/rook-ceph-operator --replicas=0
   kubectl -n rook-ceph scale deploy/rook-ceph-mgr --replicas=0
   ```

### Validation

- `kubectl -n rook-ceph get cephcluster rook-ceph` reports `status.ceph.health=HEALTH_OK`.
- `ceph status` and `ceph osd tree` show monitors and OSDs in `up/in` state.
- `flux reconcile kustomization rook-ceph-cluster --with-source` completes with healthy checks.
- `velero restore describe <name>` reports `Phase: Completed` without warnings.
- Storage classes are available and PVCs can be provisioned successfully.

### Troubleshooting Guidance

Refer to the dedicated [Troubleshooting](#troubleshooting) section after performing the above validation.

### Escalation

- Engage storage on-call with recent `ceph status`, `kubectl -n rook-ceph get events`, and the Flux commit SHA.
- Loop in Talos owners if node or etcd instability contributes to storage issues.
- Coordinate with backup owners before manipulating Velero backup objects.
- Capture `ceph crash ls` and `ceph crash info <id>` outputs prior to external escalation.

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
| `task validate`                                                             | Runs repository schema validation (kubeconform, yamllint, conftest). |
| `task dev-env:lint`                                                         | Executes markdownlint, prettier, and ancillary linters.              |
| `flux diff hr rook-ceph-operator --namespace rook-ceph`                     | Previews rendered Helm changes before reconciliation.                |
| `flux diff hr rook-ceph-cluster --namespace rook-ceph`                      | Previews rendered Helm changes before reconciliation.                |

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

3. Address the root cause (resolve backfill delays, restart pods, fix network partitions) and continue monitoring until `HEALTH_OK` returns.

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

   If hardware failed, follow the removal and replacement steps in the Day-2 operations phase.

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

4. Ensure node plugins can map RBD devices; restart relevant DaemonSet pods if mount errors persist.

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

3. Retry with `--restore-volumes=false` when PVC data remains intact but CRDs need reseeding.
4. Reconcile operator CRDs to ensure correct versions:

   ```bash
   flux reconcile kustomization rook-ceph-operator --with-source
   ```

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

- **`dashboard-admin`** – Created per-realm for Ceph Dashboard integration with RGW
- **`rgw-admin-ops-user`** – Created on-demand when ObjectBucketClaim or CephBucketNotification resources are deployed

### Validation Commands

```bash
# Check object stores are healthy
kubectl get cephobjectstore -n rook-ceph

# Check RGW pods (should see 4 pods: 2 per store)
kubectl get pods -n rook-ceph -l app=rook-ceph-rgw

# Check StorageClasses exist
kubectl get storageclass | grep ceph-bucket

# List RGW users in a realm
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- radosgw-admin user list --rgw-realm=fast

# Check RGW pools
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph osd pool ls | grep rgw
```

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

- **`preservePoolsOnDelete: false`** – Pools are deleted when CephObjectStore is removed. GitOps provides protection; manual deletion requires explicit pool removal.
- **Dashboard integration** – SSO config and zone system_key setup handled by init container in toolbox deployment (see `release.yaml` postRenderers).
- **Default realm** – `fast` is set as the global default realm/zonegroup/zone for dashboard display.

## Grafana Dashboard Integration

The Ceph Dashboard embeds Grafana panels for metrics visualization. This requires specific configuration in both Grafana and Ceph.

### Requirements

1. **Dashboard1 datasource** – The Ceph Dashboard hardcodes `var-datasource=Dashboard1` in iframe URLs. A Grafana datasource named exactly "Dashboard1" must exist pointing to Prometheus/VictoriaMetrics.

2. **Official ceph-mixin dashboards** – The Ceph Dashboard expects dashboards with specific UIDs from the [ceph-mixin](https://github.com/ceph/ceph/tree/main/monitoring/ceph-mixin/dashboards_out):

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

3. **Grafana embedding** – Enable iframe embedding in Grafana config:

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

- **Custom dashboards** – `cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/`
- **Dashboard ConfigMaps** – `cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml`
- **Dashboard1 datasource** – `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml` under `defaultDatasources.extra`

### References

- [Ceph Dashboard Grafana integration source](https://github.com/ceph/ceph/blob/main/src/pybind/mgr/dashboard/frontend/src/app/shared/components/grafana/grafana.component.ts)
- [Ceph mixin dashboards](https://github.com/ceph/ceph/tree/main/monitoring/ceph-mixin/dashboards_out)
