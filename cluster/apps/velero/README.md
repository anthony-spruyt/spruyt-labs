# Velero Backup Runbook

## Purpose and Scope

Velero provides disaster recovery and workload-level backups for the spruyt-labs
Talos Kubernetes cluster. This runbook documents how operators provision the
Velero control plane, integrate it with Rook-Ceph CSI snapshots, capture
cluster-scoped resources, and execute restores ranging from single namespace
recovery to full cluster rebuilds. All guidance aligns with the repository-wide
runbook standards and
assumes GitOps reconciliation through Flux.

## Architecture Overview

- **Flux-managed HelmRelease** – Velero is deployed through the Helm controller
  defined in
  [`cluster/apps/velero/velero/app/release.yaml`](velero/app/release.yaml) and
  reconciled by Flux.
- **Backup targets** – Primary object storage resides in an S3-compatible
  bucket. Credentials are delivered via the encrypted secret referenced by the
  Helm values.
- **CSI integration** – Rook-Ceph snapshot classes expose `VolumeSnapshot`
  resources that Velero consumes for PersistentVolume backups.
- **Node agent** – The Restic/FSB node agent is enabled to protect filesystems
  that lack CSI snapshot support.
- **Talos control plane** – kubeconfig and credentials are sourced from Talos
  APIs; Talos etcd recovery workflows complement Velero restores during
  full-cluster disaster recovery.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                                 | Description                                                               |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| [`cluster/apps/velero/kustomization.yaml`](kustomization.yaml)                       | Entry point that wires the namespace and Flux Kustomization for Velero.   |
| [`cluster/apps/velero/namespace.yaml`](namespace.yaml)                               | Namespace manifest and pod security annotations for Velero controllers.   |
| [`cluster/apps/velero/velero/app/kustomization.yaml`](velero/app/kustomization.yaml) | Packages the HelmRelease and values ConfigMap via Kustomize.              |
| [`cluster/apps/velero/velero/app/values.yaml`](velero/app/values.yaml)               | Helm chart values covering plugins, snapshot defaults, and secret wiring. |
| [`cluster/apps/velero/velero/app/release.yaml`](velero/app/release.yaml)             | Flux `HelmRelease` definition pointing at the VMware Tanzu Velero chart.  |
| [`cluster/apps/velero/velero/ks.yaml`](velero/ks.yaml)                               | Flux `Kustomization` that reconciles the HelmRelease into the cluster.    |
| `../../.taskfiles/dev-env/tasks.yaml`                                                | Task runner entries for installing the Velero CLI and related tooling.    |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Work inside the devcontainer or ensure local versions of `talosctl`, `kubectl`,
  `flux`, `velero`, `task`, and `yq` match repository tooling expectations.
- Possess decrypted access to the Velero S3 credentials (`age` identity and SOPS
  keys) and export `AWS_*` variables when validating buckets manually.
- Confirm the Talos control plane is healthy and that you can retrieve an
  up-to-date admin kubeconfig.
- Verify Rook-Ceph snapshot classes exist (`kubectl get volumesnapshotclass`) and
  that backup schedules defined in Git cover critical namespaces.

## Operational Runbook

### Summary

Provision and operate Velero so that cluster configuration, namespace workloads,
and Ceph-backed PersistentVolumes are continuously protected. Execute restores in
a controlled fashion while maintaining schedule hygiene and credential integrity.

### Preconditions

- Git working tree clean or dedicated feature branch prepared for promotion.
- Flux control plane healthy:

  ```bash
  flux check
  flux get kustomizations -n flux-system
  ```

- Current Talos kubeconfig fetched and exported:

  ```bash
  talosctl --nodes <control-plane-ip> kubeconfig /tmp/spruyt-kubeconfig
  export KUBECONFIG=/tmp/spruyt-kubeconfig
  ```

- S3 bucket reachability validated from the operator workstation:

  ```bash
  aws s3 ls s3://<velero-bucket>
  ```

- Rook-Ceph health confirmed before running destructive restores:

  ```bash
  task rook-ceph:tools
  # inside toolbox
  ceph status
  ```

### Procedure

#### Phase 0 – Tooling and credential preparation

1. Install or update the Velero CLI for local validation:

   ```bash
   task dev-env:install-velero
   velero version
   ```

2. Decrypt and inspect the credential secret if rotation or validation is
   required:

   ```bash
   sops -d cluster/apps/velero/velero/app/velero-secret.sops.yaml | yq '.'
   ```

3. Confirm Talos can reach the object store endpoint (required for node-agent
   pods) by verifying outbound connectivity in `talosctl` logs if changes are
   planned.

#### Phase 1 – Reconcile Velero control plane

1. Reconcile the namespace and Helm release:

   ```bash
   flux reconcile kustomization velero --with-source
   flux reconcile kustomization velero-app --with-source
   ```

   (Adjust names if Flux Kustomizations differ in the repository.)

2. Validate controller pods and node agents:

   ```bash
   kubectl -n velero get pods
   kubectl -n velero logs deploy/velero -c velero --tail=50
   ```

3. Check the backup storage location and volume snapshot location status:

   ```bash
   velero backup-location get
   velero snapshot-location get
   ```

4. Confirm CSI snapshot classes match Rook-Ceph storage classes:

   ```bash
   kubectl get volumesnapshotclass
   ```

5. Ensure the `velero-secret` exists and references correct credentials:

   ```bash
   kubectl -n velero get secret velero-secret -o yaml
   ```

#### Phase 2 – Capture workloads and cluster-scoped resources

1. Create or reconcile scheduled backups for critical namespaces:

   ```bash
   velero schedule create critical-daily \
     --schedule="0 2 * * *" \
     --include-namespaces rook-ceph,flux-system,kube-system \
     --ttl=240h \
     --snapshot-volumes=true
   velero schedule get
   ```

2. Run an ad-hoc cluster configuration backup that includes cluster-scoped
   resources:

   ```bash
   velero backup create cluster-config-$(date +%Y%m%d%H%M) \
     --include-cluster-resources \
     --default-volumes-to-restic=false \
     --wait
   velero backup describe cluster-config-$(date +%Y%m%d%H%M)
   ```

3. Validate CSI snapshots for Ceph-backed PersistentVolumes:

   ```bash
   kubectl get volumesnapshot -A
   kubectl describe volumesnapshot -n <namespace> <snapshot-name>
   ```

4. Ensure restic repositories are healthy for workloads without CSI support:

   ```bash
   velero backup logs <backup-name> | grep restic
   ```

5. Commit schedule definitions or label adjustments back to Git and reconcile via
   Flux:

   ```bash
   flux reconcile kustomization cluster-apps --with-source
   ```

#### Phase 3 – Restore workflows (namespaced and full-cluster DR)

1. Gather current backup inventory and identify restore points:

   ```bash
   velero backup get
   velero restore get
   ```

2. **Namespaced restore** – Rehydrate a single workload while preserving live
   PersistentVolumes:

   ```bash
   velero restore create ns-restore-$(date +%Y%m%d%H%M) \
     --from-backup critical-daily \
     --include-namespaces <target-namespace> \
     --restore-volumes=true \
     --wait
   velero restore describe ns-restore-$(date +%Y%m%d%H%M)
   kubectl get pods -n <target-namespace>
   ```

   Resolve conflicts by deleting stale Deployments or CRDs before rerunning the
   restore when necessary.

3. **Full cluster DR** – Combine Velero, Rook-Ceph, and Talos etcd workflows:

   ```bash
   flux suspend kustomization cluster-apps
   talosctl --nodes <control-plane-ip> etcd status
   velero restore create cluster-dr-$(date +%Y%m%d%H%M) \
     --from-backup cluster-config-latest \
     --include-cluster-resources \
     --wait
   ```

   - After Velero completes, restore Ceph data if snapshots were rolled back
     manually:

     ```bash
     task rook-ceph:tools
     # inside toolbox
     ceph status
     rbd snap ls <pool>/<image>
     ```

- Follow Talos etcd recovery guidance
  if control-plane nodes required replacement.

- Resume GitOps once validation succeeds:

  ```bash
  flux resume kustomization cluster-apps
  flux reconcile kustomization cluster-apps --with-source
  ```

4. Archive restore logs for audit:

   ```bash
   velero restore logs cluster-dr-$(date +%Y%m%d%H%M) > ~/cluster-dr.log
   ```

#### Phase 4 – Maintenance, hygiene, and lifecycle tasks

1. Verify schedules and last-success timestamps weekly:

   ```bash
   velero schedule get -o wide
   ```

2. Rotate S3 credentials:

   - Issue new IAM credentials.
   - Update `velero-secret` via SOPS:

     ```bash
     sops cluster/apps/velero/velero/app/velero-secret.sops.yaml
     flux reconcile kustomization velero --with-source
     ```

3. Prune stale backups to honor retention policies:

   ```bash
   velero backup delete cluster-config-20240101 --confirm
   velero backup garbage-collect
   ```

4. Validate node agent DaemonSet and restic repositories monthly:

   ```bash
   kubectl -n velero get daemonset/velero-node-agent -o wide
   velero restic repo get
   ```

5. Reconcile manifests after Git updates or chart upgrades:

   ```bash
   flux reconcile kustomization velero --with-source
   ```

### Validation

- `velero backup describe <name>` returns `Phase: Completed` with `Warnings: 0`.
- `velero restore get` shows recent operations in `Completed` state before
  workloads are handed back to application owners.
- `kubectl get volumesnapshot -A` lists snapshots that match retention policies
  with `ReadyToUse=True`.
- `flux reconcile kustomization velero --with-source` finishes without condition
  failures.
- Rook-Ceph reports `HEALTH_OK` after any restore that touched PersistentVolume
  data.

### Troubleshooting Guidance

- Review `velero backup logs <name>` for restic transfer failures or S3 upload
  errors before escalating.
- Inspect `kubectl -n velero logs deploy/velero -c velero` for API throttling,
  credential issues, or plugin panics.
- Validate snapshot availability through
  `kubectl describe volumesnapshotcontents <name>` and cross-reference Ceph
  status when PVC recovery stalls.
- For GitOps drift, reconcile the Flux Kustomization and confirm no pending
  commits remain.

### Escalation

- Engage the backup on-call with Velero backup and restore names, relevant log
  excerpts, and Flux commit SHAs.
- Loop in the storage team if snapshot reuse fails or `ceph status` reports
  `HEALTH_WARN` or `HEALTH_ERR`.
- Coordinate with Talos platform owners for etcd instability, machine
  replacement, or kubeconfig regeneration.
- Escalate to application owners once infrastructure components are stable and
  namespace restores require data validation.

## Validation and Testing

### Automated checks

- `task dev-env:lint` – Executes markdownlint, YAML schema, and policy checks
  before committing runbook updates.
- `npx markdownlint-cli2 cluster/apps/velero/README.md` – Enforces documentation
  style for this runbook.
- `flux reconcile kustomization velero --with-source` – Forces GitOps sync and
  reports Helm release success or failure.
- `velero backup get --status=Completed` – Provides a quick health gauge for
  scheduled backups.
- `kubectl get volumesnapshotclass` and `kubectl get volumesnapshot -A` – Confirm
  CSI integration remains functional.

### Manual verification

- After a restore, validate pods, PVCs, and services within target namespaces:

  ```bash
  kubectl get pods,pvc,svc -n <namespace>
  ```

- Run `velero restore describe <name>` and confirm no error messages appear.
- Use the Rook toolbox (`task rook-ceph:tools`) to run `ceph status` and
  `ceph fs mount ls` when PVC-bound workloads are restored.
- Confirm Flux resumed reconciliation post-restore:

  ```bash
  flux get kustomizations -A | grep -E 'velero|cluster-apps'
  ```

- Execute application smoke tests or manual functional checks per service owner
  runbooks before closing incidents.

## Troubleshooting

### Backup failures (S3 authentication or restic errors)

1. Describe the backup for warnings:

   ```bash
   velero backup describe <backup-name>
   ```

2. Inspect upload logs for credential issues:

   ```bash
   velero backup logs <backup-name> | grep -i "access denied"
   ```

3. Verify credentials:

   ```bash
   kubectl -n velero get secret velero-secret \
     -o jsonpath="{.data.cloud}" | base64 --decode
   ```

4. Re-run the backup using fresh credentials or by re-synchronizing the secret
   through Git:

   ```bash
   flux reconcile kustomization velero --with-source
   velero backup create retry-$(date +%s) \
     --from-schedule <schedule-name> \
     --wait
   ```

### Restore conflicts and duplicate resources

1. Identify conflicts:

   ```bash
   velero restore describe <restore-name>
   velero restore logs <restore-name> | grep -i conflict
   ```

2. Delete offending resources (CRDs, Deployments, PVCs) before retrying:

   ```bash
   kubectl delete deployment <name> -n <namespace>
   ```

3. Re-run the restore with selective inclusion:

   ```bash
   velero restore create retry-$(date +%s) \
     --from-backup <backup-name> \
     --include-resources deployments,configmaps,secrets \
     --wait
   ```

### Missing PVCs or volume data

1. Inspect `VolumeSnapshot` and `VolumeSnapshotContent` objects:

   ```bash
   kubectl get volumesnapshot,volumesnapshotcontent -A
   ```

2. Verify Ceph snapshot presence and health:

   ```bash
   task rook-ceph:tools
   # inside toolbox
   rbd snap ls <pool>/<image>
   ```

3. If snapshots exist but binding fails, recreate the PVC and re-run the restore
   with `--restore-volumes=false`, then manually map the RBD snapshot.

4. Check node-agent logs for restic repository corruption and run
   `velero restic repo check --repo <name>`.

### CSI snapshot issues

1. Describe the `VolumeSnapshotClass` to ensure `deletionPolicy` and secrets
   align with Rook configuration:

   ```bash
   kubectl describe volumesnapshotclass <class-name>
   ```

2. Confirm the snapshot-controller deployment is healthy:

   ```bash
   kubectl -n kube-system get deploy/snapshot-controller
   ```

3. If snapshots remain pending, reconcile the Rook CSI components and Velero:

   ```bash
   flux reconcile kustomization rook-ceph-cluster --with-source
   flux reconcile kustomization velero --with-source
   ```

4. For Talos nodes, inspect `talosctl -n <node-ip> logs kubelet` for CSI
   attachment errors.

## References and Cross-links

- Rook-Ceph storage operations: [cluster/apps/rook-ceph/rook-ceph-cluster/README.md](/cluster/apps/rook-ceph/rook-ceph-cluster/README.md)
- Flux GitOps control plane: [cluster/flux/README.md](/cluster/flux/README.md)
- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Velero taskfile: [.taskfiles/dev-env/tasks.yaml](/.taskfiles/dev-env/tasks.yaml)
- Talos machine lifecycle: [Talos docs machine-lifecycle.md](/cluster/talos/docs/machine-lifecycle.md)
- Velero upstream documentation: <https://velero.io/docs/>
- AWS plugin reference: <https://github.com/vmware-tanzu/velero-plugin-for-aws>
- GitOps integration pattern: monitor Flux Kustomizations with
  `flux get kustomizations -n flux-system` after restores or credential
  rotations.
