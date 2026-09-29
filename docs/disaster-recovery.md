# Disaster Recovery

Recovering nodes, etcd, Ceph and application data. For a full rebuild, start with [bootstrap.md](bootstrap.md) and come back here for the data.

## What Is Backed Up

| Data                                | Mechanism                                                         | Where                         | Retention |
| ----------------------------------- | ----------------------------------------------------------------- | ----------------------------- | --------- |
| Desired state (all manifests)       | Git                                                               | GitHub                        | -         |
| Kubernetes objects, all namespaces  | Velero schedule `spruyt-labs-cluster-backup`, daily               | S3 (`aws-primary`)            | 25 days   |
| PVC contents                        | Velero, **only PVCs labelled** `velero.io/backup-volumes: "true"` | S3 (`aws-primary`)            | 25 days   |
| PostgreSQL (every `*-cnpg-cluster`) | CNPG barman-cloud plugin, daily base + WAL                        | S3, one `ObjectStore` per app | 7 days    |
| etcd                                | Manual snapshots only                                             | Wherever you saved them       | -         |

Any PVC without the label is **not** backed up off-cluster; it only has Ceph replication. List the ones that are:

```bash
kubectl get pvc -A -l velero.io/backup-volumes=true
```

## Preconditions

- Devcontainer with `talosctl`, `kubectl`, `flux`, `velero` and the `kubectl cnpg` plugin.
- Valid `talosconfig` (`task talos:talosconfig` regenerates it from the secrets bundle) and kubeconfig.
- For Velero and CNPG restores: the cluster is up, Flux is reconciling, and the S3 credentials in the SOPS secrets are still valid. Check with `velero backup-location get` (expect `aws-primary Available`).

## Replace a Node

Use when a node's hardware is dead or swapped. The node keeps its hostname and address.

1. If the node is still reachable, drain it. Set `noout` first when it is a worker, so Ceph does not start rebalancing:

   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

2. For a control-plane node, remove its etcd member from a surviving control plane:

   ```bash
   talosctl -n <surviving-cp-ip> etcd members
   talosctl -n <surviving-cp-ip> etcd remove-member <member-id>
   ```

   **Verify:** `etcd members` lists two members.

3. Remove the stale Node object:

   ```bash
   kubectl delete node <node-name>
   ```

4. Update disk serials in Git for the new hardware and push:

   - Install disk: `talos/patches/node/<node-name>/01-configure-install-disk.yaml` (`disk.serial`).
   - Workers only, Ceph disk: `devicePathFilter` in [`rook-ceph-cluster/app/values.yaml`](../cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml).

   Read the serials from the new node once it is in maintenance mode:

   ```bash
   talosctl -n <node-ip> get disks --insecure
   ```

5. Boot the new node from the SecureBoot ISO for its class (see the [schematics table](../talos/README.md#talos-image-schematics)) and apply its config:

   ```bash
   task talos:apply NODE='^<node-name>$'
   ```

   If `topf` cannot reach the node in maintenance mode, apply a rendered config instead:

   ```bash
   task talos:render
   talosctl apply-config --insecure -n <node-ip> --file talos/clusterconfig/topf/<node-name>.yaml
   ```

6. **Verify:** the node is `Ready`, and for a control plane, etcd is back to three members:

   ```bash
   kubectl get nodes
   talosctl -n <cp-1-ip>,<cp-2-ip>,<cp-3-ip> etcd status
   ```

7. Workers: unset `noout` and wait for Ceph to settle. A replaced OSD disk comes up as a new OSD; retire the old ID with the remove-OSD flow in [rook-ceph/README.md](../cluster/apps/rook-ceph/README.md).

   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
   ```

   **Good:** `health: HEALTH_OK`, 3 OSDs `up` and `in`, all PGs `active+clean`.

## Restore etcd (Quorum Lost)

Only when two or more control planes have lost etcd. This rolls the whole cluster back to the snapshot. Procedure from the [Talos disaster recovery guide](https://docs.siderolabs.com/talos/v1.14/build-and-extend-talos/cluster-operations-and-maintenance/disaster-recovery).

1. Get a snapshot. Prefer a recent one taken with `talosctl etcd snapshot`. With no quorum, copy the raw database from a surviving control plane instead:

   ```bash
   talosctl -n <cp-ip> cp /var/lib/etcd/member/snap/db .
   ```

2. On every control plane whose etcd is not healthy, wipe the EPHEMERAL partition. EPHEMERAL is LUKS2-encrypted; Talos re-encrypts the empty partition on the next boot, and STATE (node identity and keys) is not touched:

   ```bash
   talosctl -n <cp-ip> reset --graceful=false --reboot --system-labels-to-wipe=EPHEMERAL
   ```

3. **Verify:** etcd is waiting on every control plane:

   ```bash
   talosctl -n <cp-ip> service etcd
   ```

   **Good:** `STATE` is `Preparing` on all three.

4. Bootstrap from the snapshot on one control plane. Add `--recover-skip-hash-check` when the file came from `talosctl cp` in step 1:

   ```bash
   talosctl -n <cp-ip> bootstrap --recover-from=./db.snapshot
   ```

5. **Verify:** three healthy members and all nodes `Ready`:

   ```bash
   talosctl -n <cp-1-ip>,<cp-2-ip>,<cp-3-ip> etcd status
   kubectl get nodes
   ```

## Ceph

Ceph recovers from a single OSD or node loss on its own; `rook-ceph-tools` runs `ceph status` to watch it. For OSD removal, replacement and health warnings, use [rook-ceph/README.md](../cluster/apps/rook-ceph/README.md). Thunderbolt ring failures are in [rook-ceph-cluster/README.md](../cluster/apps/rook-ceph/rook-ceph-cluster/README.md).

## Restore a PostgreSQL Database (CNPG)

A CNPG `Cluster` only honours `bootstrap` when it is created. Restoring means creating the cluster with `bootstrap.recovery` instead of `bootstrap.initdb`. The steps below follow the n8n restore of December 2025; the commented block at the top of `cluster/apps/n8n-system/n8n/app/n8n-cnpg-cluster.yaml` is the template.

**During a full rebuild, do this before Flux creates the cluster.** Otherwise Flux creates an empty database with `initdb` and you have to delete it first.

1. **Verify** a backup exists:

   ```bash
   kubectl -n <namespace> get backups.postgresql.cnpg.io
   ```

   **Good:** recent entries with phase `completed`. On a fresh cluster these CRs are gone; the data is still in S3.

2. If the cluster exists, stop Flux from recreating it, then delete it. **This destroys the current database.**

   ```bash
   flux suspend kustomization <app>
   kubectl -n <namespace> delete clusters.postgresql.cnpg.io <app>-cnpg-cluster
   ```

3. Edit `<app>-cnpg-cluster.yaml` in Git:

   ```yaml
   spec:
     bootstrap:
       recovery:
         source: origin
         database: <db>
         owner: <owner>
         secret:
           name: <app>-cnpg-owner
         # Optional point-in-time target:
         # recoveryTarget:
         #   targetTime: "<YYYY-MM-DD HH:MM:SS.00000+TZ>"
     externalClusters:
       - name: origin
         plugin:
           name: barman-cloud.cloudnative-pg.io
           parameters:
             barmanObjectName: <app>-cnpg-aws-object-store
             serverName: <app>-cnpg-cluster
   ```

   Keep `database`, `owner` and `secret` the same as the cluster's `initdb` block. The backup holds the owner password from when it was taken; `secret` makes CNPG reset it to the current ESO-generated one, so the app can still log in.

   Comment out the `spec.plugins` WAL-archiver entry while restoring. The restored cluster would otherwise archive into the same `serverName` path it is reading from, and the plugin refuses a non-empty archive.

4. Push, then resume Flux:

   ```bash
   flux resume kustomization <app>
   ```

5. **Verify:**

   ```bash
   kubectl cnpg status <app>-cnpg-cluster -n <namespace>
   ```

   **Good:** `Cluster in healthy state`, all instances ready.

6. Revert the Git change to `bootstrap.initdb` and re-enable `spec.plugins`. `bootstrap` is ignored after creation, so reverting it does nothing to the running cluster. Take a fresh base backup once archiving is back:

   ```bash
   kubectl cnpg backup <app>-cnpg-cluster -n <namespace> --method plugin --plugin-name barman-cloud.cloudnative-pg.io
   ```

## Restore from Velero

Velero depends on Flux having deployed it and on its S3 location being `Available`.

1. List backups and inspect the one to use:

   ```bash
   velero backup get
   velero backup describe <backup-name> --details
   ```

2. Restore one namespace at a time:

   ```bash
   velero restore create <restore-name> --from-backup <backup-name> \
     --include-namespaces <namespace> --wait
   ```

   Velero skips any object that already exists, and that includes PVCs. A PVC that Flux has already recreated empty is not overwritten, so its data is not restored.

3. **Verify:**

   ```bash
   velero restore describe <restore-name>
   ```

   **Good:** `Phase: Completed` with no errors. Check `velero restore logs <restore-name>` for warnings about skipped objects.

## Full Cluster Rebuild

1. Build the cluster with [bootstrap.md](bootstrap.md) up to and including Flux.
2. Restore PostgreSQL databases (see [Restore a PostgreSQL Database](#restore-a-postgresql-database-cnpg)).
3. Restore labelled PVCs with Velero (see [Restore from Velero](#restore-from-velero)).
4. Run the final checks table in [bootstrap.md](bootstrap.md#5-final-checks).

## Related

- [talos/README.md](../talos/README.md) - Talos tasks and schematics
- [rook-ceph/README.md](../cluster/apps/rook-ceph/README.md) - Ceph operations
- [velero/README.md](../cluster/apps/velero/velero/README.md) - Velero
- [nut-system/README.md](../cluster/apps/nut-system/README.md) - UPS shutdown and recovery
