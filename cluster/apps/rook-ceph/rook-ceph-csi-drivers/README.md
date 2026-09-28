# rook-ceph-csi-drivers - Ceph CSI Driver Configuration

## Overview

Since Rook v1.20 the CSI drivers are managed by the standalone ceph-csi-operator, which Rook deploys (`installCsiOperator: true`) as `ceph-csi-controller-manager`. This chart only renders the `OperatorConfig` and the two `Driver` CRs (`csi.ceph.io/v1`) that the operator turns into the provisioner and node-plugin workloads. It creates no workloads itself.

## Operations

### Ownership split

- **This chart owns**: `OperatorConfig/ceph-csi-operator-config`, `Driver/rook-ceph.rbd.csi.ceph.com`, `Driver/rook-ceph.cephfs.csi.ceph.com`.
- **Rook owns - do not template here**: `CephConnection/rook-ceph`. Rook creates it from the `CephCluster` and fills `readAffinity` from `cephClusterSpec.csi.readAffinity` in `rook-ceph-cluster`. The chart's `cephConnections` value is left empty; an entry would create a competing CR.

### Driver-name prefix

Driver names keep the `rook-ceph.` prefix to match existing StorageClasses and VolumeSnapshotClasses. Unprefixed names would orphan every existing PV.

### Where former operator `csi.*` settings went

| Old operator `csi.*` key        | New location                                             |
| ------------------------------- | -------------------------------------------------------- |
| `readAffinity.enabled`          | `CephCluster.spec.csi.readAffinity` (rook-ceph-cluster)  |
| `enableCSIEncryption` + KMS     | `drivers.rbd.encryption.configMapRef.name`               |
| `cephFSKernelMountOptions`      | `drivers.cephfs.kernelMountOptions` (`ms_mode: secure`)  |
| `forceCephFSKernelClient: true` | `drivers.cephfs.cephFsClientType: kernel`                |
| `csiRBDProvisionerResource`     | `drivers.rbd.controllerPlugin.resources`                 |
| `enableMetadata`                | dropped - CRD field deprecated and ignored by the driver |
| `enableLiveness`                | dropped - never scraped; chart exposes no enable toggle  |

## Troubleshooting

1. **`helm template` fails with `mapping values are not allowed` on operatorConfig.yaml**

   - **Symptom**: Setting `operatorConfig.driverSpecDefaults.nodePlugin.resources` produces invalid YAML (chart bug: that path is rendered with `nindent 4`).
   - **Resolution**: Define `nodePlugin.resources` per driver (`drivers.rbd.nodePlugin.resources`, `drivers.cephfs.nodePlugin.resources`) instead. The per-driver template indents correctly.

2. **HelmRelease fails to install: `invalid ownership metadata`**

   - **Symptom**: Helm refuses to adopt a `Driver`/`OperatorConfig` CR that Rook created at runtime without Helm labels.
   - **Resolution**: The live CRs need `app.kubernetes.io/managed-by: Helm` plus `meta.helm.sh/release-name: rook-ceph-csi-drivers` / `meta.helm.sh/release-namespace: rook-ceph` before the first reconcile. Relabel - do not delete, deletion disrupts the data path - and reconcile again.

3. **rbd Driver patch fails: `spec.encryption.configMapName: Required value`**

   - **Symptom**: Chart 1.0.1 renders `spec.encryption.configMapRef`, but the Driver CRD bundled with rook-ceph-operator only accepts `spec.encryption.configMapName`. CRD validation fails and wedges the rbd controller plugin. CephFS is unaffected (no encryption block).
   - **Resolution**: A `postRenderers` patch in `app/release.yaml` rewrites the field to `configMapName` (#2208). Keep encryption - encrypted RBD StorageClasses depend on it. Remove the patch once the chart renders `configMapName`.

4. **rbd controller plugin stuck 0/2: `serviceaccount "rbd-ctrlplugin-sa" not found`**

   - **Symptom**: The rbd Driver's `spec.controllerPlugin.serviceAccountName` is empty, so the operator (env `CSI_SERVICE_ACCOUNT_PREFIX=""`) falls back to the legacy unprefixed SA, which does not exist. Usually a side effect of a failed first install (for example the encryption error above) where helm-controller never wrote the field.

   - **Resolution**: The rendered chart already sets the prefixed SAs; once the blocking error is fixed a clean reconcile converges. To restore the data path immediately, patch the live Driver:

     ```bash
     kubectl -n rook-ceph patch driver rook-ceph.rbd.csi.ceph.com --type=merge -p '{"spec":{"controllerPlugin":{"serviceAccountName":"rook-ceph-rbd-csi-ceph-com-ctrlplugin-sa"},"nodePlugin":{"serviceAccountName":"rook-ceph-rbd-csi-ceph-com-nodeplugin-sa"}}}'
     ```

     Ref [rook/rook#17644](https://github.com/rook/rook/issues/17644).

5. **RBD ReclaimSpaceJobs fail: `node Client not found for <node> nodeID`**

   - **Symptom**: Every RBD `ReclaimSpaceJob` fails. The rbd nodeplugin pod has no `csi-addons` sidecar and the live Driver has `spec.deployCsiAddons: false` although `values.yaml` sets `true`. CephFS is unaffected.
   - **Cause**: Rook wrote the Driver CR first and owns `spec.deployCsiAddons` via SSA (its default `false`). Helm's 3-way merge sees no diff against its own rendered value and never patches it, so a plain reconcile cannot fix it.
   - **Resolution**: `driftDetection.mode: enabled` in `app/release.yaml` makes helm-controller force-apply the rendered manifest, reclaiming the field. That in turn needs the empty-object (`{}`) resource subkeys in `values.yaml`: when `resources` is set, the chart renders every subkey and unset ones become `null`, which the Driver CRD rejects on the SSA dry-run drift detection performs. Removing
     either `driftDetection` or the empty-object subkeys breaks all RBD ReclaimSpaceJobs again.

6. **All csi-addons containers CrashLoopBackOff: `invalid value "0" for flag -v: invalid log level "0"`**

   - **Symptom**: Right after a csi-addons sidecar image bump every `csi-addons` container fails: both ctrlplugin Deployments go 0/2 and both `-nodeplugin-csi-addons` DaemonSets crash-loop. Provisioning, attach, resize and snapshot stop; mounted volumes keep serving I/O.
   - **Cause**: The operator renders `--v={{ log.verbosity }}` on every CSI container. Sidecar v0.15.0 moved to controller-runtime zap and aliased `--v` to `--zap-log-level`, which accepts `debug`/`info`/`error`/`panic` or an integer **greater than 0**. The operator's default of `0` is no longer valid.
   - **Resolution**: Keep `log.verbosity` at `1` or higher in **all three** places in `values.yaml` - `operatorConfig.driverSpecDefaults.log`, `drivers.rbd.log` and `drivers.cephfs.log`. The chart renders `spec.log` into both Driver CRs, and the operator only falls back to `driverSpecDefaults` when `spec.log` is nil, so setting the default alone does nothing.
   - **Ordering**: The sidecar tag is set in `rook-ceph-operator` values and verbosity here, and Flux reconciles the operator first. A Reloader annotation on `ceph-csi-controller-manager` restarts it as soon as the image set changes, so a single push carrying both changes rolls the new image while verbosity is still `0`. Push the verbosity change first, let all six workloads converge, then push
     the image bump (#2711). Verbosity `1` adds negligible log volume.

## References

- [ceph-csi-operator](https://github.com/ceph/ceph-csi-operator)
- [Rook v1.20 CSI drivers chart](https://rook.io/docs/rook/v1.20/Helm-Charts/csi-drivers-chart/)
