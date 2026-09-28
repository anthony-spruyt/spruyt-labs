# Velero - Cluster Backup

## Overview

Nightly backup of all Kubernetes resources to S3, plus data-mover copies of the few PVCs that opt in. Databases are **not** covered here - CNPG backs up through Barman (see [plugin-barman-cloud](../../cnpg-system/plugin-barman-cloud/README.md)). Restore procedures are in [`docs/disaster-recovery.md`](../../../../docs/disaster-recovery.md).

## Prerequisites

- S3 bucket and IAM user from [`infra/terraform/aws/velero-backup/`](../../../../infra/terraform/aws/velero-backup/README.md). The access key goes by hand into the `cloud` key of `app/velero-secret.sops.yaml` (AWS credentials-file format). The Terraform README's `kubectl create secret` example uses a different secret name; the one used here is `velero-secret`.

## Operations

### PVC data is opt-in

`resources/volume-policy.yaml` snapshots only PVCs labelled `velero.io/backup-volumes: "true"` and skips everything else. Label the **PVC**, not the pod. Snapshots use the RBD `VolumeSnapshotClass` labelled `velero.io/csi-volumesnapshot-class` and are moved to S3 by the node-agent (`snapshotMoveData`), so a backup survives the loss of the Ceph cluster.

### Non-default settings

- **Kopia full GC** (`fullMaintenanceInterval: eagerGC` in the `backup-repo-config` ConfigMap): without it Kopia only runs quick maintenance and expired backup data is never deleted from S3 (#1170). The `--backup-repository-configmap` flag must be set under **both** `configuration.extraArgs` (server) and `nodeAgent.extraArgs` - the chart passes the former only to the server Deployment, and the
  node-agent does the data movement (#3097).
- **BSL/VSL are plain manifests** in `resources/`, not chart values (`backupsEnabled`/`snapshotsEnabled: false`), so they are applied by the separate `velero-resources` Kustomization after the CRDs exist.
- **`image.tag` is set explicitly** rather than following the chart's appVersion. It was introduced to pick up the CSI restore fix in v1.18.1 ([vmware-tanzu/velero#9515](https://github.com/vmware-tanzu/velero/issues/9515)) before the chart shipped it, and Renovate now bumps it independently of the chart - keep the plugin image compatible when it moves.

## References

- [Velero CSI snapshot data movement](https://velero.io/docs/main/csi-snapshot-data-movement/)
- [Velero resource policies](https://velero.io/docs/main/resource-filtering/#resource-policies)
