# rook-ceph-csi-drivers - Ceph CSI Operator Driver Configuration

## Overview

Critical-infrastructure tier (data path). As of Rook v1.20, CSI driver management is removed from the `rook-ceph` operator chart and delegated to the standalone [ceph-csi-operator](https://github.com/ceph/ceph-csi-operator). This component deploys the `ceph-csi-drivers` Helm chart, which renders the `Driver` and `OperatorConfig` custom resources (`csi.ceph.io/v1`) that configure the RBD and CephFS
CSI drivers.

The chart itself creates **no** workloads — only CRs, ServiceAccounts, and RBAC. The `ceph-csi-controller-manager` (deployed by the Rook operator via `installCsiOperator: true`) reconciles these CRs into the actual CSI provisioner and node-plugin pods.

Values mirror the spec Rook previously applied to the live CRs on the v1.19.x cluster, so adoption by Helm does not degrade replicas, hostNetwork, resource requests, or snapshot policy.

## Prerequisites

- `rook-ceph-operator` (from `ks.yaml` `dependsOn`) — provides the `ceph-csi-controller-manager` and the `csi.ceph.io` CRDs.

## Operations

### Ownership split (what this chart owns vs what Rook owns)

- **This chart owns**: `OperatorConfig/ceph-csi-operator-config`, `Driver/rook-ceph.rbd.csi.ceph.com`, `Driver/rook-ceph.cephfs.csi.ceph.com`.
- **Rook owns (do NOT template here)**: `CephConnection/rook-ceph`. Rook auto-creates it from the `CephCluster` CR (owner ref `ClientProfile/rook-ceph`) and populates `spec.readAffinity.crushLocationLabels` from `cephClusterSpec.csi.readAffinity` in the `rook-ceph-cluster` values. The chart's `cephConnections` value is therefore left empty — adding an entry would create a competing CR.

### Driver-name prefix

Driver names keep the `rook-ceph.` prefix (`rook-ceph.rbd.csi.ceph.com`, `rook-ceph.cephfs.csi.ceph.com`) to match existing StorageClasses / VolumeSnapshotClasses. Unprefixed names would orphan all existing PVs.

### Migrating former `rook-ceph` operator `csi.*` settings

| Old operator `csi.*` key        | New location                                             |
| ------------------------------- | -------------------------------------------------------- |
| `readAffinity.enabled`          | `CephCluster.spec.csi.readAffinity` (rook-ceph-cluster)  |
| `enableCSIEncryption` + KMS     | `drivers.rbd.encryption.configMapRef.name`               |
| `cephFSKernelMountOptions`      | `drivers.cephfs.kernelMountOptions` (`ms_mode: secure`)  |
| `forceCephFSKernelClient: true` | `drivers.cephfs.cephFsClientType: kernel`                |
| `csiRBDProvisionerResource`     | `drivers.rbd.controllerPlugin.resources`                 |
| `enableMetadata`                | dropped — CRD field deprecated and ignored by the driver |
| `enableLiveness`                | dropped — never scraped; chart exposes no enable toggle  |

## Troubleshooting

1. **`helm template` fails with `mapping values are not allowed` on operatorConfig.yaml**

   - **Symptom**: Setting `operatorConfig.driverSpecDefaults.nodePlugin.resources` produces invalid YAML (chart bug: that path is rendered with `nindent 4`).
   - **Resolution**: Define `nodePlugin.resources` per-driver (`drivers.rbd.nodePlugin.resources`, `drivers.cephfs.nodePlugin.resources`) instead of in `operatorConfig.driverSpecDefaults`. The per-driver template path indents correctly.

2. **HelmRelease fails to install: `invalid ownership metadata`**

   - **Symptom**: Helm refuses to adopt a `Driver`/`OperatorConfig` CR that Rook created at runtime without Helm labels.
   - **Resolution**: The live CRs must carry `app.kubernetes.io/managed-by: Helm` plus `meta.helm.sh/release-name: rook-ceph-csi-drivers` / `meta.helm.sh/release-namespace: rook-ceph` before first reconcile. Relabel (do not delete — deletion disrupts the data path) and re-reconcile.

## References

- [ceph-csi-operator](https://github.com/ceph/ceph-csi-operator)
- [Rook v1.20 CSI Drivers chart](https://rook.io/docs/rook/v1.20/Helm-Charts/csi-drivers-chart/)
- [Rook v1.20 CSI Configuration](https://rook.io/docs/rook/v1.20/Storage-Configuration/Ceph-CSI/csi-configuration/)
