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

3. **rbd Driver patch fails: `spec.encryption.configMapName: Required value`**

   - **Symptom**: Chart 1.0.1 renders `spec.encryption.configMapRef`, but the Driver CRD v1.0.1 (bundled with rook-ceph-operator) only accepts `spec.encryption.configMapName`. The field-name mismatch fails CRD validation and wedges the rbd controller plugin. CephFS is unaffected (no encryption block).
   - **Resolution**: A HelmRelease `postRenderers` kustomize patch in `release.yaml` rewrites the rbd Driver encryption field to `configMapName`. Keep encryption — encrypted RBD StorageClasses depend on it. Remove the patch once the upstream chart renders `configMapName`.

4. **rbd controller plugin stuck 0/2: `serviceaccount "rbd-ctrlplugin-sa" not found`**

   - **Symptom**: The rbd Driver's `spec.controllerPlugin.serviceAccountName` is empty, so the operator (env `CSI_SERVICE_ACCOUNT_PREFIX=""`) falls back to the legacy unprefixed SA `rbd-ctrlplugin-sa`, which does not exist. Typically a side effect of a failed first install (e.g. the encryption error above) where `helm-controller` never wrote the SA field; CephFS installs clean and is unaffected.
   - **Resolution**: The chart's rendered desired-state already sets the prefixed SA (`rook-ceph-rbd-csi-ceph-com-{ctrl,node}plugin-sa`); once the blocking error is fixed, a clean reconcile converges. To restore the data path immediately, patch the live Driver:
     `kubectl -n rook-ceph patch driver rook-ceph.rbd.csi.ceph.com --type=merge -p '{"spec":{"controllerPlugin":{"serviceAccountName":"rook-ceph-rbd-csi-ceph-com-ctrlplugin-sa"},"nodePlugin":{"serviceAccountName":"rook-ceph-rbd-csi-ceph-com-nodeplugin-sa"}}}'`. Ref [rook/rook#17644](https://github.com/rook/rook/issues/17644).

5. **RBD ReclaimSpaceJobs fail: `node Client not found for <node> nodeID`**

   - **Symptom**: Every `ReclaimSpaceJob` for RBD PVCs fails after retries. The rbd nodeplugin pod has no `csi-addons` sidecar. The live `Driver/rook-ceph.rbd.csi.ceph.com` has `spec.deployCsiAddons: false` even though `values.yaml` sets it `true`. CephFS reclaim is unaffected.
   - **Cause**: The rook operator wrote the Driver CR first and owns `spec.deployCsiAddons` via SSA (value `false`, its default). Helm's 3-way merge sees no diff against its own rendered value and emits no corrective patch, so rook's `false` persists. A plain reconcile cannot fix it.
   - **Resolution**: `driftDetection.mode: enabled` in `release.yaml` makes `helm-controller` force-apply the rendered manifest via SSA, reclaiming the field and setting it `true`. This requires the empty-object (`{}`) resource subkeys in `values.yaml`: when `resources` is set, the chart renders every subkey, and unset ones emit `null`, which the Driver CRD rejects (`must be object`) on the SSA
     dry-run that drift detection performs. Do not remove `driftDetection` or the empty-object subkeys — either regresses all RBD ReclaimSpaceJobs.

## References

- [ceph-csi-operator](https://github.com/ceph/ceph-csi-operator)
- [Rook v1.20 CSI Drivers chart](https://rook.io/docs/rook/v1.20/Helm-Charts/csi-drivers-chart/)
- [Rook v1.20 CSI Configuration](https://rook.io/docs/rook/v1.20/Storage-Configuration/Ceph-CSI/csi-configuration/)
