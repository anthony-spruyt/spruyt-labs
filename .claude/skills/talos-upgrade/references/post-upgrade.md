# Phases 5 to 7: Post-Upgrade Validation, Rebalancing and talos/README.md

## Phase 5: Post-upgrade validation

**Run ALL checks to confirm successful upgrade:**

```bash
# Parallel Group 1 - Version verification
talosctl version --nodes "$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' ',')" --short
kubectl get nodes -o wide

# Parallel Group 2 - Cluster health
talosctl health -n <any-cp-node-ip>
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>

# Parallel Group 3 - Storage and GitOps
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
flux get kustomizations -A
flux get helmreleases -A
```

**Ceph heartbeat cleanup:** follow the Step 4.5 stale heartbeat instructions in [ceph-recovery.md](ceph-recovery.md).

## Phase 6: Workload rebalancing (optional)

After all nodes are upgraded and Ceph is healthy, rebalance pods across the rebooted nodes. The descheduler already runs on a schedule as the `kube-system/descheduler` CronJob; a manual run rebalances now instead of at the next tick. Skip it if distribution already looks balanced.

```bash
kubectl create job --from=cronjob/descheduler descheduler-manual-$(date +%s) -n kube-system
```

Once the job completes, count pods per node with `kubectl get pods -A -o wide`.

## Phase 7: Update talos/README.md

`talos/README.md` "Talos Image Schematics" is the only place that pins the Talos version in docs; the runbooks in `docs/` link to it. Update it on main — do not open a separate docs PR.

1. Replace `v<old-version>` with `v<new-version>` in the ISO, UKI and upgrade-image columns:

   ```bash
   grep -n "v<old-version>" talos/README.md
   ```

2. Confirm the Schematic ID column still matches the live IDs from [Schematic Discovery](discovery.md#schematic-discovery). If a class's ID changed, update the ID in every column of that row.

3. Land only `talos/README.md`, by the landing rule in the skill.
