# Cluster Maintenance

Recurring and planned operations: health checks, Talos config changes, node reboots, Talos and Kubernetes upgrades, and credential expiry. Recovery from failures is in [disaster-recovery.md](disaster-recovery.md).

## Preconditions

- Devcontainer with a valid `talosconfig` and kubeconfig (see [DEVELOPMENT.md](../DEVELOPMENT.md)).
- `SOPS_AGE_KEY_FILE` set for any `task talos:*` command. They decrypt `talos/*.sops.yaml` in memory.
- Talos commands need `-n <node-ip>`; addresses come from `kubectl get nodes -o wide`. Control-plane nodes are `e2-1`..`e2-3`, workers are `ms-01-1`..`ms-01-3`.

## Health Check

Run before and after any disruptive change. Everything must be good before you start.

| Check       | Command                                                           | Good                                  |
| ----------- | ----------------------------------------------------------------- | ------------------------------------- |
| Nodes       | `kubectl get nodes -o wide`                                       | 6 `Ready`, same Talos and K8s version |
| etcd        | `talosctl -n <cp-1-ip>,<cp-2-ip>,<cp-3-ip> etcd status`           | 3 members, no errors                  |
| Ceph        | `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status` | `HEALTH_OK`, all PGs `active+clean`   |
| Flux        | `flux get kustomizations -A --status-selector ready=false`        | No rows                               |
| Talos drift | `task talos:diff`                                                 | Exit code 0                           |
| Backups     | `velero backup get`                                               | Latest daily backup `Completed`       |

`task talos:diff` exits non-zero when it finds drift. That means drift, not a broken command.

## Talos Config Changes

Talos config is **not** reconciled by Flux. A merged change does nothing until someone applies it. Patch layering and ordering rules are in [talos/README.md](../talos/README.md#patch-layering).

1. Edit `talos/topf.yaml` or `talos/patches/**`, then preview:

   ```bash
   task talos:diff
   ```

   The diff says whether each node needs a reboot. Reordering list entries (for example `machine.udev.rules`) shows up as a change and can force a reboot.

2. Merge the change to `main`, then apply. `topf` asks for confirmation and applies control planes one at a time. Limit it to one node with `NODE`:

   ```bash
   task talos:apply NODE='^<node-name>$'
   task talos:apply
   ```

3. **Verify:** `task talos:diff` exits 0, and the [health check](#health-check) passes.

## Reboot or Power Off a Node

For hardware work or a stuck node. One node at a time.

1. Run the [health check](#health-check). Ceph must be `HEALTH_OK`.

2. Workers only: stop Ceph from rebalancing while the node's OSD is down:

   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd set noout
   ```

3. Reboot, or shut down for hardware work:

   ```bash
   talosctl -n <node-ip> reboot
   talosctl -n <node-ip> shutdown
   ```

   Do not cordon a worker by hand. The Ceph mon and OSD on it are pinned to that host and stay `Pending` until the node is uncordoned.

4. **Verify:** the node is back:

   ```bash
   kubectl wait --for=condition=Ready node/<node-name> --timeout=10m
   ```

   Control planes: `etcd status` shows 3 members again.

5. Workers: clear the flag and wait for Ceph:

   ```bash
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
   kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
   ```

   **Good:** `HEALTH_OK`. A leftover `noout` shows as `HEALTH_WARN ... noout flag(s) set`.

## Talos OS Upgrade

Renovate bumps `talosVersion` in `talos/topf.yaml`. Upgrade the nodes first, then merge the pin: `task talos:apply` renders `machine.install.image` from the pin, so applying before the nodes run the new version rolls them back.

1. Preconditions:

   - The [health check](#health-check) passes.

   - The target release's supported Kubernetes range includes `kubernetesVersion` in `talos/topf.yaml` (see the Talos release notes).

   - For a **minor** upgrade, render against the target version and validate each node's config. `topf render` also rewrites `talos/talenv.sops.yaml` and `talos/talsecret.sops.yaml`; discard those changes afterwards:

     ```bash
     # with talosVersion temporarily set to the target in talos/topf.yaml
     task talos:render
     talosctl validate --config talos/clusterconfig/topf/<node-name>.yaml --mode metal
     git checkout -- talos/topf.yaml talos/talenv.sops.yaml talos/talsecret.sops.yaml
     ```

2. Take an etcd snapshot and keep it off-cluster:

   ```bash
   talosctl -n <cp-ip> etcd snapshot etcd-<date>.snapshot
   ```

3. Build the installer image for each hardware class. The current one is on every node; keep the schematic and change the tag:

   ```bash
   kubectl get node <node-name> -o jsonpath='{.metadata.annotations.installerImage}'
   ```

   **Good:** `factory.talos.dev/metal-installer-secureboot/<schematic-id>:<current-version>`. Control planes and workers use different schematic IDs.

4. Control planes, one at a time. Point `-e` at a **different** control plane; the VIP can land on the node being upgraded and drop the connection:

   ```bash
   talosctl upgrade -n <cp-ip> -e <other-cp-ip> \
     --image factory.talos.dev/metal-installer-secureboot/<cp-schematic-id>:<target-version>
   ```

   **Verify** before the next node: `kubectl get nodes -o wide` shows the new Talos version for this node, and `etcd status` shows 3 members.

5. Workers, one at a time. First check that no PodDisruptionBudget would block the drain:

   ```bash
   kubectl get pdb -A
   ```

   If any row shows `ALLOWED DISRUPTIONS` of `0`, add `--drain=false`. Otherwise the drain evicts the Ceph mon and OSD, times out on the blocked pod, aborts before upgrading and leaves the node cordoned. If that happens, run `kubectl uncordon <node-name>` and retry with `--drain=false`.

   ```bash
   talosctl upgrade -n <worker-ip> -e <cp-ip> \
     --image factory.talos.dev/metal-installer-secureboot/<worker-schematic-id>:<target-version>
   ```

   **Verify** before the next worker: node `Ready` on the new version, and `ceph status` back to `HEALTH_OK` (a few minutes). Do not move on while Ceph is degraded.

6. Merge the `talosVersion` bump (and update the schematic table in [talos/README.md](../talos/README.md)), then bring the machine config in line:

   ```bash
   task talos:diff
   task talos:apply
   ```

   **Good:** the first diff shows only the installer image; after the apply, `task talos:diff` exits 0.

## Kubernetes Upgrade

Renovate bumps `kubernetesVersion` in `talos/topf.yaml`. Talos upgrades the control plane components and kubelets.

1. Run the [health check](#health-check), take an etcd snapshot (step 2 of the Talos upgrade), and check the Kubernetes changelog for removed APIs still in use.

2. Dry run, then upgrade:

   ```bash
   talosctl -n <cp-ip> upgrade-k8s --to <version> --dry-run
   talosctl -n <cp-ip> upgrade-k8s --to <version>
   ```

   The dry run must succeed. The upgrade is safe to re-run if it stops partway.

3. **Verify:** `kubectl get nodes` shows the new version on all six nodes, and the health check passes.

4. Kubelet restarts can leave secret volumes in already-running pods frozen at their old contents. Restart Deployments that mount rotated secrets. Restart Ceph pods one at a time, waiting for `HEALTH_OK` between each.

5. Update the version in the other places that pin it, then merge: `talos/topf.yaml`, `.github/workflows/_kubeconform.yaml` and `.taskfiles/install/scripts/install-kubectl.sh`.

## etcd

- A `kube-system/etcd-defrag` CronJob defragments etcd weekly ([etcd-defrag/README.md](../cluster/apps/kube-system/etcd-defrag/README.md)).

- There are **no automatic etcd snapshots**. Take one before any upgrade or control-plane change:

  ```bash
  talosctl -n <cp-ip> etcd snapshot etcd-<date>.snapshot
  ```

## Credential Expiry

| Credential                   | Check                                          | Renew                    |
| ---------------------------- | ---------------------------------------------- | ------------------------ |
| Talos client (`talosconfig`) | `talosctl config info` (`Certificate expires`) | `task talos:talosconfig` |
| Ingress TLS                  | Auto-renewed by cert-manager                   | -                        |

## Terraform

Terraform Cloud workspaces are VCS-driven: merging to `main` queues a run for the workspace whose path changed, and you confirm the apply in the Terraform Cloud UI. Before pushing:

```bash
task terraform:fmt
task terraform:validate
```

See [infra/README.md](../infra/README.md) for the workspaces.

## Renovate

Renovate config is centralised in `anthony-spruyt/repo-operator`. Repo overrides and testing are in [.claude/rules/06-renovate.md](../.claude/rules/06-renovate.md).

## Diagnostics

A privileged shell on a node (host PID, network and root filesystem at `/rootfs`):

```bash
task dev-env:priv-pod node=<node-name>
```

## Related

- [talos/README.md](../talos/README.md) - patch layering, schematics
- [rook-ceph/README.md](../cluster/apps/rook-ceph/README.md) - Ceph operations
- [disaster-recovery.md](disaster-recovery.md) - recovery procedures
