# Rook-Ceph Storage Runbook

## Overview

Rook-Ceph provides distributed storage services for Kubernetes workloads, including block storage (RBD), shared filesystem storage (CephFS), and object storage (RGW). This runbook documents the GitOps layout, deployment workflow, and operations for maintaining Rook-Ceph in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.
- Include comprehensive decision trees for autonomous storage operations.
- Define performance baselines and monitoring commands for storage systems.
- Document cross-service dependencies and MCP integration workflows.

## Current Version

- **Operator Chart Version**: v1.18.7 (rook-ceph)
- **Cluster Chart Version**: v1.18.7 (rook-ceph-cluster)
- **Last Updated**: Check `cluster/apps/rook-ceph/rook-ceph-operator/app/release.yaml` and `cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml` for current pinned versions

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                                                                                      | Description                                                                              |
| ----------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| [`cluster/apps/rook-ceph/README.md`](README.md)                                                                                           | This runbook and component overview.                                                     |
| [`cluster/apps/rook-ceph/kustomization.yaml`](kustomization.yaml)                                                                         | Root Kustomize entry that wires the namespace, operator, and cluster overlays.           |
| [`cluster/apps/rook-ceph/namespace.yaml`](namespace.yaml)                                                                                 | Namespace definition with pod-security labels suitable for privileged storage workloads. |
| [`cluster/apps/rook-ceph/rook-ceph-operator`](rook-ceph-operator)                                                                         | Flux Kustomization and HelmRelease for the operator deployment.                          |
| [`cluster/apps/rook-ceph/rook-ceph-operator/ks.yaml`](rook-ceph-operator/ks.yaml)                                                         | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.                  |
| [`cluster/apps/rook-ceph/rook-ceph-operator/app/kustomization.yaml`](rook-ceph-operator/app/kustomization.yaml)                           | Overlay combining the HelmRelease and generated values ConfigMap.                        |
| [`cluster/apps/rook-ceph/rook-ceph-operator/app/release.yaml`](rook-ceph-operator/app/release.yaml)                                       | Flux `HelmRelease` referencing the upstream rook-ceph operator chart.                    |
| [`cluster/apps/rook-ceph/rook-ceph-operator/app/values.yaml`](rook-ceph-operator/app/values.yaml)                                         | Rendered values supplied to the chart via ConfigMap.                                     |
| [`cluster/apps/rook-ceph/rook-ceph-cluster`](rook-ceph-cluster)                                                                           | Flux Kustomization and HelmRelease for the Ceph cluster resources.                       |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/ks.yaml`](rook-ceph-cluster/ks.yaml)                                                           | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.                  |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/app/kustomization.yaml`](rook-ceph-cluster/app/kustomization.yaml)                             | Overlay combining the HelmRelease and generated values ConfigMap.                        |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml`](rook-ceph-cluster/app/release.yaml)                                         | Flux `HelmRelease` referencing the upstream rook-ceph-cluster chart.                     |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml`](rook-ceph-cluster/app/values.yaml)                                           | Helm values configuring Ceph networking, encryption, resources, devices, and monitoring. |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/app/config-maps.yaml`](rook-ceph-cluster/app/config-maps.yaml)                                 | Additional ConfigMaps for cluster configuration.                                         |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage`](rook-ceph-cluster/storage)                                                           | Storage overlays defining pools, storage classes, and snapshot classes.                  |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage/block`](rook-ceph-cluster/storage/block)                                               | RBD block pools, `StorageClass`, and `VolumeSnapshotClass` definitions.                  |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage/filesystem`](rook-ceph-cluster/storage/filesystem)                                     | CephFS filesystem pools and storage classes.                                             |
| [`cluster/apps/rook-ceph/rook-ceph-cluster/storage/object`](rook-ceph-cluster/storage/object)                                             | Object store and user manifests for Ceph RGW (enabled as required).                      |
| [`cluster/flux/meta/repositories/oci/rook-ceph-ocirepo.yaml`](../../../flux/meta/repositories/oci/rook-ceph-ocirepo.yaml)                 | OCI repository definition pinning the upstream Rook Ceph operator source.                |
| [`cluster/flux/meta/repositories/oci/rook-ceph-cluster-ocirepo.yaml`](../../../flux/meta/repositories/oci/rook-ceph-cluster-ocirepo.yaml) | OCI repository definition pinning the upstream Rook Ceph cluster source.                 |
| [`.taskfiles/rook-ceph/tasks.yaml`](../../../.taskfiles/rook-ceph/tasks.yaml)                                                             | Task runner target that opens an interactive shell in the toolbox deployment.            |

<!-- markdownlint-enable MD013 -->

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

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of Rook-Ceph tasks, including storage health checks, OSD management, and recovery from failures.

### Storage Health Status Workflow

```bash
If kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph.health}' | grep -v "HEALTH_OK" > /dev/null
Then:
  For each failing component:
    Run ceph health detail
    Expected output: Detailed health status and warnings
    If status shows "HEALTH_WARN":
      Run ceph orch ps --daemon-type mon,mgr,osd
      Expected output: Daemon status showing problematic services
      Recovery: Restart affected daemons or investigate specific warnings
    Else if status shows "HEALTH_ERR":
      Run ceph crash ls
      Expected output: List of recent crashes
      Recovery: Analyze crash data and restart critical daemons
  Else:
    Proceed to OSD health check
Else:
  Proceed to OSD health check
```

### OSD Health Monitoring Workflow

```bash
If ceph osd tree | grep -E "down|out" > /dev/null
Then:
  For each failing OSD:
    Run ceph osd status | grep <osd-id>
    Expected output: OSD status and failure reason
    If OSD shows "down":
      Run kubectl -n rook-ceph get pods -l app=rook-ceph-osd | grep <osd-id>
      Expected output: Pod status for the OSD
      Recovery: Restart OSD pod or investigate node issues
    Else if OSD shows "out":
      Run ceph orch daemon restart osd.<id>
      Expected output: Daemon restart confirmation
      Recovery: Wait for OSD to rejoin cluster
  Else:
    OSDs verified healthy
Else:
  OSDs verified healthy
```

### Storage Capacity Management Workflow

```bash
If ceph df | grep -E "FULL|NEARFULL" > /dev/null
Then:
  For each near-full pool:
    Run ceph osd pool stats <pool-name>
    Expected output: Pool usage statistics
    If pool usage > 85%:
      Run ceph osd pool set <pool> size 3
      Expected output: Replication size adjustment
      Recovery: Increase replication or add storage capacity
    Else if pool usage > 75%:
      Run ceph osd pool set <pool> pg_num <higher-value>
      Expected output: Placement group count adjustment
      Recovery: Optimize placement groups for better distribution
  Else:
    Capacity within thresholds
Else:
  Capacity within thresholds
```

### Velero Backup Validation Workflow

```bash
If velero backup get | grep rook-ceph | grep -v "Completed" > /dev/null
Then:
  For each incomplete backup:
    Run velero backup describe <backup-name>
    Expected output: Backup status and failure details
    If backup shows "InProgress":
      Run velero backup logs <backup-name>
      Expected output: Backup operation logs
      Recovery: Wait for completion or investigate stalls
    Else if backup shows "Failed":
      Run velero backup logs <backup-name> | grep -i error
      Expected output: Error messages from backup process
      Recovery: Retry backup or fix underlying issues
  Else:
    Backups verified successfully
Else:
  Backups verified successfully
```

## Machine-Readable Decision Trees

### Storage Health Check Decision Tree

```yaml

```

## Decision tree for automated storage health monitoring

start: "check_storage_health"
nodes:
check_storage_health:
question: "Is Ceph cluster healthy?"
command: "kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph.health}'"
yes: "storage_healthy"
no: "investigate_health_issues"
investigate_health_issues:
action: "Run ceph health detail and analyze warnings/errors"
next: "check_osd_status"
check_osd_status:
question: "Are all OSDs operational?"
command: "ceph osd tree | grep -E 'down|out'"
yes: "check_pool_capacity"
no: "handle_osd_failures"
handle_osd_failures:
action: "For each failing OSD: ceph orch daemon restart osd.<id>"
next: "verify_osd_recovery"
verify_osd_recovery:
question: "OSDs recovered successfully?"
command: "ceph osd tree | grep -v -E 'down|out'"
yes: "check_pool_capacity"
no: "escalate_osd_issue"
check_pool_capacity:
question: "Are storage pools within capacity thresholds?"
command: "ceph df | grep -E 'FULL|NEARFULL'"
yes: "storage_healthy"
no: "manage_pool_capacity"
manage_pool_capacity:
action: "Adjust replication size or placement groups as needed"
next: "verify_capacity_fix"
verify_capacity_fix:
question: "Capacity issues resolved?"
command: "ceph df | grep -v -E 'FULL|NEARFULL'"
yes: "storage_healthy"
no: "escalate_capacity_issue"
escalate_osd_issue:
action: "Escalate OSD failures with ceph crash logs and pod status"
next: "end"
escalate_capacity_issue:
action: "Escalate capacity issues with pool statistics and usage data"
next: "end"
storage_healthy:
action: "Storage health verified successfully"
next: "end"
end: "end"

### OSD Management Decision Tree

```yaml
# Decision tree for OSD lifecycle management
start: "osd_management_start"
nodes:
  osd_management_start:
    question: "What OSD operation is needed?"
    options:
      add_osd: "Add new OSD"
      remove_osd: "Remove existing OSD"
      restart_osd: "Restart problematic OSD"
      check_osd_health: "Check OSD health status"
  add_osd:
    action: "ceph orch device ls && ceph orch daemon add osd <host>:<device>"
    next: "verify_osd_addition"
  remove_osd:
    action: "ceph osd out <id> && ceph orch daemon rm osd.<id> --force"
    next: "verify_osd_removal"
  restart_osd:
    action: "ceph orch daemon restart osd.<id>"
    next: "verify_osd_restart"
  check_osd_health:
    action: "ceph osd tree && ceph osd status"
    next: "analyze_osd_health"
  verify_osd_addition:
    question: "OSD added successfully?"
    command: "ceph osd tree | grep <new-osd-id>"
    yes: "osd_operation_complete"
    no: "retry_osd_addition"
  verify_osd_removal:
    question: "OSD removed successfully?"
    command: "ceph osd tree | grep -v <removed-osd-id>"
    yes: "osd_operation_complete"
    no: "retry_osd_removal"
  verify_osd_restart:
    question: "OSD restarted successfully?"
    command: "ceph osd tree | grep <restarted-osd-id> | grep -v down"
    yes: "osd_operation_complete"
    no: "retry_osd_restart"
  analyze_osd_health:
    question: "OSD health issues detected?"
    command: "ceph osd tree | grep -E 'down|out'"
    yes: "handle_osd_health_issues"
    no: "osd_operation_complete"
  handle_osd_health_issues:
    action: "Investigate and remediate OSD health problems"
    next: "verify_health_resolution"
  verify_health_resolution:
    question: "OSD health issues resolved?"
    command: "ceph osd tree | grep -v -E 'down|out'"
    yes: "osd_operation_complete"
    no: "escalate_osd_health"
  retry_osd_addition:
    action: "Retry OSD addition with corrected parameters"
    next: "verify_osd_addition"
  retry_osd_removal:
    action: "Retry OSD removal with force flag"
    next: "verify_osd_removal"
  retry_osd_restart:
    action: "Retry OSD restart and check logs"
    next: "verify_osd_restart"
  escalate_osd_health:
    action: "Escalate persistent OSD health issues"
    next: "end"
  osd_operation_complete:
    action: "OSD operation completed successfully"
    next: "end"
end: "end"
```

### Command Templates

```yaml

```

## Template for storage diagnostics

storage_commands:
cluster_health: "kubectl -n rook-ceph get cephcluster rook-ceph"
ceph_status: "ceph status"
ceph_health: "ceph health detail"
osd_tree: "ceph osd tree"
osd_status: "ceph osd status"
pool_stats: "ceph osd pool stats <pool>"
crash_list: "ceph crash ls"
crash_info: "ceph crash info <id>"
daemon_restart: "ceph orch daemon restart <daemon-type>.<id>"
pod_logs: "kubectl -n rook-ceph logs <pod-name>"
storage_classes: "kubectl get storageclass | grep rook"
pvc_status: "kubectl get pvc -A | grep rook"
velero_backups: "velero backup get | grep rook-ceph"
velero_describe: "velero backup describe <name>"

## Performance Baselines

### Performance Threshold Constants

```yaml
# Performance threshold constants for automated monitoring
performance_thresholds:
  cpu_usage_warning: 70 # Percentage
  cpu_usage_critical: 85
  memory_usage_warning: 75
  memory_usage_critical: 90
  disk_usage_warning: 80
  disk_usage_critical: 95
  response_time_warning: 500 # Milliseconds
  response_time_critical: 2000
  error_rate_warning: 1 # Percentage
  error_rate_critical: 5
  pod_restart_rate_warning: 3 # Per hour
  pod_restart_rate_critical: 10
  storage_latency_warning: 100 # ms for storage operations
  storage_latency_critical: 500
  iops_threshold_warning: 1000 # IOPS per OSD
  iops_threshold_critical: 5000
```

### Storage Performance Baselines

```yaml

```

## Performance baselines for Rook-Ceph operations

performance_baselines:
cluster_health_check:
threshold: "30s"
monitoring_command: "kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph.health}'"
osd_health_check:
threshold: "60s"
monitoring_command: "ceph osd tree | grep -c 'up'"
storage_latency:
threshold: "50ms"
monitoring_command: "ceph osd perf | awk '{print $4}' | head -1"
storage_throughput:
threshold: "100MB/s"
monitoring_command: "ceph osd perf | awk '{print $6}' | head -1"
resource_usage:
cpu:
threshold: "60%"
monitoring_command: "kubectl top pods -n rook-ceph --no-headers | awk '{print $3}' | head -1"
memory:
threshold: "2Gi"
monitoring_command: "kubectl top pods -n rook-ceph --no-headers | awk '{print $4}' | head -1"
availability:
threshold: "99.9%"
monitoring_command: "kubectl get pods -n rook-ceph --no-headers | grep -c 'Running'"
pool_capacity:
threshold: "80%"
monitoring_command: "ceph df | grep -v 'FULL|NEARFULL' | wc -l"
osd_distribution:
threshold: "balanced"
monitoring_command: "ceph osd tree | grep -c 'up'"

## Cross-Service Dependencies

### Required Dependencies

```yaml
# Cross-service dependency mapping for Rook-Ceph
service_dependencies:
  rook_ceph:
    depends_on:
      - flux_system
      - talos_control_plane
      - velero_backup
    depended_by:
      - authentik
      - traefik
      - all_persistent_workloads
    critical_path: true
    health_check_command: "kubectl -n rook-ceph get cephcluster rook-ceph -o jsonpath='{.status.ceph.health}'"
```

### Dependency Health Checks

```bash
# Check all dependencies
check_dependencies() {
  echo "Checking Rook-Ceph Dependencies..."

  # Flux System
  if ! kubectl get kustomizations -n flux-system | grep -q rook-ceph; then
    echo "❌ Flux kustomization missing"
    return 1
  fi

  # Talos Control Plane
  if ! talosctl --nodes <control-plane-ip> health | grep -q "healthy"; then
    echo "❌ Talos control plane unhealthy"
    return 1
  fi

  # Velero Backup
  if ! velero backup get | grep -q rook-ceph; then
    echo "❌ Velero backups missing"
    return 1
  fi

  # Storage Classes
  if ! kubectl get storageclass | grep -q rook; then
    echo "❌ Storage classes missing"
    return 1
  fi

  echo "✅ All dependencies present"
  return 0
}
```

## Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools for Rook-Ceph tasks

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Rook-Ceph documentation (e.g., "rook/rook-ceph", "rook/rook-ceph-cluster").
- Confirm the catalog entry contains the documentation or API details needed for Rook-Ceph operations.
- Note the library identifier, source description, and any version information that appears in the catalog.

### When the catalog covers Rook-Ceph documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts on Rook-Ceph CRDs, Helm chart values, or troubleshooting guides.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Rook-Ceph configuration changes (e.g., OSD configuration, storage pool setup, upgrade procedures).

### When Rook-Ceph documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation (e.g., "Rook-Ceph Helm chart configuration for Kubernetes storage management").
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage for Rook-Ceph Operations

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Rook-Ceph change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Rook-Ceph documentation, especially when deviating from upstream defaults.

### After Rook-Ceph changes

- Ensure the relevant rule or runbook references the same library ID so future contributors reuse consistent sources.
