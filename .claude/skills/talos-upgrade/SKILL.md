---
name: talos-upgrade
description: >
  Use when a Renovate PR bumps talosVersion in talos/topf.yaml, the user asks to upgrade Talos OS across the cluster,
  planned maintenance needs node upgrades, or a post-incident rebuild moves nodes to a newer Talos version. Upgrades one
  node at a time. Not for Kubernetes-only upgrades (use kubernetes-upgrade), config changes without a version bump, or
  single-node troubleshooting (use talosctl directly).
argument-hint: <target-version>
---

# Talos Upgrade

Safely upgrade Talos OS across the cluster while preserving etcd quorum (control plane) and Ceph data availability (workers). Cluster stability is paramount. Control plane nodes go first, one at a time (3 CP nodes = need 2 healthy minimum), then workers, one at a time with a Ceph gate between each. Patch upgrades swap the installer image; minor upgrades also migrate machine config to new document types.

This skill runs in the main session, so it runs qa-validator, commits, pushes, merges and asks the owner itself. Where a step lands changes on main, run qa-validator with the upgrade issue number and the changed files, commit with `Ref #<issue>`, push to main, then continue at the same step.

`$` followed by a digit is an argument placeholder: substitution runs over this whole file, including code fences, so commands that use awk fields like that live in the reference files.

## GitHub Issue Tracking

Track upgrade work with a GitHub issue. If no issue exists, create one with title `chore(talos): upgrade Talos v<current> to v<target>` and label `infra`, body filled from the infra form with the upgrade-specific values in [references/templates.md](references/templates.md) ("Issue body").

Use plain lists, not checkboxes, in the issue body: checkboxes are hard to edit reliably. Post per-node progress as comments (example in the templates file), and edit the body when the plan changes.

## Discovery

Discover node IPs at runtime rather than hardcoding them; they are kept out of the repo and can change. Get schematics from live nodes, not from documentation or `topf.yaml` (which may be outdated). Commands for topology, schematic and version detection, and the Phase 3 node lookups: [references/discovery.md](references/discovery.md).

## Upgrade Workflow

### Phase 0: Input Validation and Upgrade Classification

1. Determine upgrade parameters:

   - Source: Renovate PR number or user-provided version
   - Read `talos/topf.yaml` to get current and target versions
   - Validate version format (vX.Y.Z)

2. Classify the upgrade. This decides whether Phase 2b runs and how Critical Safety Rule 10 applies:

| Classification | Example            | Config migration                                 |
| -------------- | ------------------ | ------------------------------------------------ |
| Patch          | v1.13.4 to v1.13.9 | None. Image swap only, skip Phase 2b             |
| Minor          | v1.13.9 to v1.14.0 | Required. Run Phase 2b before touching any node  |
| Major          | v1.x to v2.x       | Stop and hand back to the user for a manual plan |

3. For a minor upgrade, read the target release notes before doing anything else:

```bash
gh release view <target-version> --repo siderolabs/talos --json body -q .body
```

Extract: new config documents emitted by default, v1alpha1 fields deprecated or moved, and the Kubernetes version shipped.

4. Verify the target Talos release supports the pinned Kubernetes version. `talos/topf.yaml` pins `kubernetesVersion` independently of `talosVersion`, and a minor Talos release can drop support for an older kubelet. Compare the pin against the release notes' component list and its supported-versions range. Stop if the pin falls outside it.

### Phase 1: Pre-Upgrade Validation

**Run ALL checks. BLOCK if any fail.**

```bash
# Parallel Group 1 - Cluster health
# talosctl health takes a single node; it discovers the cluster from there
talosctl health -n <any-cp-node-ip>
kubectl get nodes -o wide

# Parallel Group 2 - etcd and storage
# CP nodes only; workers answer etcd calls with "Unimplemented"
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Parallel Group 3 - GitOps
flux get kustomizations -A
flux get helmreleases -A
```

**Parallel Group 4 - Eviction blockers (determines worker drain strategy — do NOT skip):** run the PDB survey in [references/worker-drain.md](references/worker-drain.md) and classify what it finds. Any PDB with `disruptionsAllowed: 0` will block a drain-based upgrade: a CNPG primary-role PDB means `--drain=false` in Phase 4, Rook's `rook-ceph-osd-host-<node>` is expected, and `rook-ceph-mon-pdb` at `ALLOWED 0` means a mon is already down: STOP, investigate first.

**Pre-upgrade checklist (all must pass):**

- [ ] All nodes report Ready in kubectl
- [ ] talosctl health passes
- [ ] etcd has 3 healthy members with consistent terms
- [ ] Ceph ready (see Step 4.1)
- [ ] All Flux kustomizations are Ready
- [ ] No pending HelmRelease upgrades/failures
- [ ] PDBs surveyed and worker drain strategy chosen
- [ ] Target installer images verified to exist for BOTH schematics (see below)
- [ ] No unapplied drift between `talos/` on main and the nodes, or it was applied (see pre-flight drift check)

**Verify installer images before starting.** The Factory builds SecureBoot assets lazily, so the first request for a new version can take 60+ seconds and may appear to hang. Retry once before concluding the image is missing:

```bash
curl -sS --max-time 60 -o /dev/null -w "%{http_code}\n" \
  "https://factory.talos.dev/v2/metal-installer-secureboot/<schematic>/manifests/<target-version>"
# Expect 200. A timeout on first call usually means the image is still being built - retry.
```

**Pre-flight drift check (before any node changes):** Renovate bumps under `talos/` merge to main without reaching the nodes; apply them now so Phase 8 shows only this upgrade's changes. Follow [references/drift-check.md](references/drift-check.md):

- Require `git status --porcelain -- talos/` to be empty, then `git pull --ff-only` and `task talos:diff`. Exit 0 means no drift: continue
- If the pin already reached main, the installer-image lines are expected: skip the pre-flight apply and record any other applyable drift for Phase 8
- Otherwise apply drift with `TOPF_CONFIRM=false task talos:apply` only if it is **applyable** (every line traces to a `talos/` commit on main, no Kubernetes version change, no reboot), then require `task talos:diff` to exit 0, re-check nodes Ready, etcd 3/3 and Ceph ready, and record the applied commit shas in the issue
- Anything else: report PRE-UPGRADE BLOCKED with the diff summary

**If ANY check fails, STOP and tell the owner** with the PRE-UPGRADE BLOCKED report ([references/templates.md](references/templates.md)).

### Phase 2: etcd Backup

Take this before any control plane upgrade:

```bash
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

SNAPSHOT=/tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot

# Streams the snapshot to this machine, not to the node
talosctl -n $CP_NODE etcd snapshot "$SNAPSHOT"
ls -l "$SNAPSHOT"
```

Post backup confirmation, with the local snapshot path, to the issue.

### Phase 2b: Config Migration (minor upgrades only)

Skip entirely for patch upgrades. For a minor upgrade the machine config has to be migrated before any node is touched, because a new Talos minor introduces config documents that the old `v1alpha1` fields collide with. Follow Steps 2b.1 to 2b.4 in [references/config-migration.md](references/config-migration.md):

- **Step 2b.1:** set the target `talosVersion`, `task talos:render`, then restore `talosVersion` and revert the SOPS side effects
- **Step 2b.2:** `talosctl validate` every node against the target contract; a clean render can still be an invalid config
- **Step 2b.3:** land the migration on main (qa-validator, commit with `Ref #<issue>`, push), then confirm `task talos:diff` is empty. **Do not begin Phase 3 with an unmerged migration.**
- **Step 2b.4:** the migrated documents reach the nodes in the Phase 8 apply, not before

### Phase 3: Control Plane Upgrades (Sequential)

One node at a time: two down at once loses etcd quorum.

For EACH control plane node:

#### Step 3.1: Get node info

Get the control plane node IPs, the cluster endpoint and the schematic from the live control plane node with the Step 3.1 commands in [references/discovery.md](references/discovery.md).

#### Step 3.2: Pre-node health check

```bash
# Verify etcd quorum before proceeding
# CP nodes only; workers answer etcd calls with "Unimplemented"
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
# Must show 3 healthy members
```

#### Step 3.3: Execute upgrade

```bash
# IMPORTANT: For CP upgrades, use a SURVIVING CP node as endpoint, NOT the cluster VIP.
# The VIP may route to the node being upgraded, causing the command to lose connection.
# Choose an endpoint that is NOT the node being upgraded.
talosctl upgrade \
  --nodes <node-ip> \
  --endpoints <surviving-cp-ip> \
  --image factory.talos.dev/metal-installer-secureboot/<schematic>:<target-version>
```

**Endpoint selection for control plane upgrades:**

| Node Being Upgraded | Use as Endpoint                |
| ------------------- | ------------------------------ |
| 1st CP node         | 2nd CP node                    |
| 2nd CP node         | 1st CP node (already upgraded) |
| 3rd CP node         | 1st CP node (already upgraded) |

#### Step 3.4: Wait for node recovery

Set `NODE_NAME` for `<node-ip>` with the Step 3.4 lookup in [references/discovery.md](references/discovery.md), then:

```bash
# Wait for node to become Ready (timeout: 5 minutes)
kubectl wait --for=condition=Ready node/$NODE_NAME --timeout=300s

# Verify Talos API is responsive
talosctl health -n <node-ip>

# Verify etcd quorum restored (must show 3 healthy)
# Target only CP nodes
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
```

**Expect the raft term to advance by 1 when you upgrade the node currently holding the leader lease.** Rebooting the leader triggers exactly one leader election. This is normal and benign.

What actually matters, and what you should verify:

- All 3 members respond
- `RAFT INDEX` is consistent across members (they may differ by a few as writes land)
- The `ERRORS` column is empty
- The term is **stable** afterwards — a term that keeps climbing across checks means flapping, which IS a problem worth stopping for

#### Step 3.5: Post-node validation

```bash
# Verify version upgraded
talosctl version --nodes <node-ip> --short
```

#### Step 3.6: Post progress to issue

Post progress to the issue after each node.

**WAIT between each control plane node:**

- Minimum 60 seconds after node Ready
- etcd quorum must show 3 healthy members
- Node must be fully Ready

### Phase 4: Worker Upgrades (Sequential with Ceph Safety)

One node at a time, and wait for Ceph between each: two workers down at once can leave PGs without a replica.

For EACH worker node:

#### Step 4.1: Pre-node Ceph check (BLOCKING)

```bash
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd tree
```

**Ceph ready** means all OSDs up and in, all PGs `active+clean`, mons in quorum, and health is either `HEALTH_OK` or `HEALTH_WARN` whose only checks are `OSD_SLOW_PING_TIME_BACK` / `OSD_SLOW_PING_TIME_FRONT` (stale reboot heartbeats, see Step 4.5) or `BLUESTORE_SLOW_OP_ALERT`. Any other warning, or any `HEALTH_ERR`, is not ready.

`BLUESTORE_SLOW_OP_ALERT` stays raised for `bluestore_slow_ops_warn_lifetime` (24h default) after a single slow op and clears when the OSD restarts, so it is acceptable only while all OSDs are up/in and all PGs are `active+clean`. Note it in the progress comment and do not restart OSDs to clear it. Live `SLOW_OPS` (slow requests) still blocks.

**BLOCK if Ceph is not ready:** stop and tell the owner with the WORKER UPGRADE BLOCKED report ([references/templates.md](references/templates.md)).

#### Step 4.2: Get worker info

```bash
# Get worker node IPs
WORKER_NODES=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')

# Get schematic from a live worker node (see Schematic Discovery)
SCHEMATIC=$(talosctl get extensions -n "${WORKER_IP}" 2>/dev/null | grep schematic | awk '{print $NF}')
```

#### Step 4.3: Execute upgrade

Default drain is fine when the Phase 1 PDB survey came back clean:

```bash
talosctl upgrade \
  --nodes <node-ip> \
  --endpoints <cp-node-ip> \
  --image factory.talos.dev/metal-installer-secureboot/<schematic>:<target-version>
```

**When to add `--drain=false`:** only if the Phase 1 survey found a PDB stuck at `disruptionsAllowed: 0`. A drain blocked by it evicts the Ceph mon and OSD, then aborts and leaves the node cordoned; raising `--drain-timeout` does not help. Read [references/worker-drain.md](references/worker-drain.md) (Step 4.3) before using `--drain=false`, and verify kubelet graceful shutdown on the live node as it shows. **Do NOT manually cordon the node as a substitute** (rule 9).

#### Step 4.3a: Recovery if a drain-based upgrade already aborted

If an upgrade aborted during drain and left the node cordoned with Ceph degraded, fix it immediately before anything else: `kubectl uncordon <hostname>`, then confirm the node was NOT upgraded before retrying with `--drain=false` (Step 4.3a in [references/worker-drain.md](references/worker-drain.md)).

#### Step 4.4: Wait for node recovery

```bash
# Wait for node to become Ready (timeout: 5 minutes)
kubectl wait --for=condition=Ready node/<hostname> --timeout=300s

# Verify Talos API is responsive
talosctl health -n <node-ip>
```

#### Step 4.4a: Kata config copy check (first worker only)

`talos/patches/worker/13-tune-kata-memory.yaml` replaces the kata-containers extension's config with a full copy, so a path or option the new extension changed breaks every Kata pod. After the first worker is back, run the config diff in [references/kata.md](references/kata.md). If it shows more than the expected differences, fix the patch yourself as that file describes and carry on with the next worker:

- Do not apply it now (rule 10). The Phase 8 apply ships it
- Before Phase 8, land it on main: run qa-validator with the upgrade issue number and the patch file, commit with `Ref #<issue>`, push, then continue at Phase 8. Nodes must not run config that isn't on main

#### Step 4.5: Wait for Ceph recovery

```bash
# Poll until Ceph is ready as defined in Step 4.1 (timeout: 30 minutes)
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
```

Expect `HEALTH_WARN` for a few minutes after the reboot, including the NOOUT flag after PGs are clean. Stale heartbeat warnings (`OSD_SLOW_PING_TIME_*`) decay on their own: judge safety by data state, not the `HEALTH_OK` string, and prefer waiting over restarting an OSD. The recovery timeline, the heartbeat checks and the only case that warrants an OSD restart are in [references/ceph-recovery.md](references/ceph-recovery.md).

#### Step 4.5a: Stale `Error` pods after node reboots

Pods in `Error` state after a node reboot are stale pod objects from the previous boot, not real failures. Leave them for garbage collection and judge health from controllers, with the commands in [references/ceph-recovery.md](references/ceph-recovery.md) (Step 4.5a).

#### Step 4.6: Post progress to issue

Post progress to the issue after each worker, including Ceph recovery time.

### Phase 5: Post-Upgrade Validation

**Run ALL checks to confirm successful upgrade:**

```bash
# Parallel Group 1 - Version verification
talosctl version --short
kubectl get nodes -o wide

# Parallel Group 2 - Cluster health
talosctl health -n <any-cp-node-ip>
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>

# Parallel Group 3 - Storage and GitOps
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
flux get kustomizations -A
flux get helmreleases -A
```

**Ceph heartbeat cleanup:** follow the Step 4.5 stale heartbeat instructions in [references/ceph-recovery.md](references/ceph-recovery.md).

### Phase 6: Workload Rebalancing (Optional)

After all nodes are upgraded and Ceph is healthy, rebalance pods across the rebooted nodes. The descheduler already runs on a schedule as the `kube-system/descheduler` CronJob; a manual run rebalances now instead of at the next tick. Skip it if distribution already looks balanced.

```bash
kubectl create job --from=cronjob/descheduler descheduler-manual-$(date +%s) -n kube-system
```

Once the job completes, count pods per node with `kubectl get pods -A -o wide`.

### Phase 7: Update talos/README.md

`talos/README.md` "Talos Image Schematics" is the only place that pins the Talos version in docs; the runbooks in `docs/` link to it. Update it on main — do not open a separate docs PR.

1. Replace `v<old-version>` with `v<new-version>` in the ISO, UKI and upgrade-image columns:

   ```bash
   grep -n "v<old-version>" talos/README.md
   ```

2. Confirm the Schematic ID column still matches the live IDs from Schematic Discovery. If a class's ID changed, update the ID in every column of that row.

3. Commit only `talos/README.md` with `Ref #<issue>` and push to main.

### Phase 8: Land the Pin and Apply Machine Config

`talosctl upgrade` only swaps the running image. The machine config on each node still carries the old `machine.install.image`, and for minor upgrades the old config documents. Run `task talos:apply` to bring it in line with the repo. Skipping this leaves the nodes drifted from `talos/topf.yaml`.

**The pin must be on main first.** `apply` renders `machine.install.image` from `talosVersion` in `talos/topf.yaml`. If you apply before the pin moves, every node goes back to the old installer image.

- **Renovate PR:** merge it with `gh pr merge <N> --squash`.
- **Manual request:** set `talosVersion` in `talos/topf.yaml`, run qa-validator with the upgrade issue number and `talos/topf.yaml`, commit the pin with `Ref #<issue>`, push to main, then continue at Phase 8.

Once the pin is on main and pulled locally, run the dry run. It's non-interactive and safe:

```bash
git pull --ff-only
task talos:diff    # exits non-zero when there is drift - that is the expected result here
```

Expected diff:

- **Patch upgrade:** only `machine.install.image` → `<schematic>:<new-version>` on each node
- **Minor upgrade:** the installer image, plus the migrated documents from Phase 2b
- **Kata config fixed in Step 4.4a:** the `kata-containers/configuration.toml` file on the workers
- **Pin merged before Phase 1:** the non-installer drift recorded in Phase 1, each line traced to a commit under `talos/` on main

Pre-existing drift was already applied in Phase 1 (or recorded there, if the pin was already on main), so anything else, such as a Kubernetes version change or unrelated patch drift, means stop and report it. Do not apply.

Apply it yourself. `topf` asks a `[y/n]` question per node on stdin; the diff you just checked is that confirmation, so turn the prompt off:

```bash
TOPF_CONFIRM=false task talos:apply
```

Then re-run `task talos:diff`. It must exit 0 (no drift). Re-check node Ready, etcd 3/3 and Ceph ready (Step 4.1), because an apply can restart services.

Smoke-test Kata on the first worker with the command in [references/kata.md](references/kata.md). **Good:** prints a kernel without the `-talos` suffix. A stuck `ContainerCreating` or sandbox error means the Kata config is broken: run the Step 4.4a diff again, fix the patch, re-apply.

If you can't finish this phase in the session (for example the pin isn't on main yet), report PARTIAL with the land-pin → diff → apply steps as the required actions. Do not report SUCCESS.

### Phase 9: Final Report

1. If the pin PR touched `cluster/`, run cluster-validator with the upgrade issue number, per `.claude/rules/validation.md`.
2. Post the completion report ("Upgrade Complete" in [references/templates.md](references/templates.md)) to the issue.
3. Close the tracking issue after cluster-validator confirms, or once the report is posted if it didn't need to run.

## Outcome

Tell the owner the outcome with the SUCCESS, ROLLBACK or PARTIAL template in [references/templates.md](references/templates.md). Post ROLLBACK and PARTIAL to the issue too; for SUCCESS, the Phase 9 completion report is the issue comment.

SUCCESS requires Phase 8 done: pin on main, apply run, clean diff. Otherwise report PARTIAL.

## Rollback Procedures

The downgrade commands for a failed control plane or worker node, and the checks for Ceph that stays degraded after a worker recovers, are in [references/rollback.md](references/rollback.md).

**If etcd quorum is lost (< 2 healthy members):** stop and report ROLLBACK to the owner. The owner runs the recovery from `docs/disaster-recovery.md` with the Phase 2 snapshot; do not run it yourself.

## Context7 Troubleshooting

On an unexpected Talos, etcd or Ceph error, look it up in Context7 (`/siderolabs/talos`, `/rook/rook`) before improvising a fix.

## Critical Safety Rules

1. **NEVER upgrade multiple control plane nodes simultaneously**
2. **ALWAYS verify etcd quorum (3 healthy) after each control plane upgrade**
3. **ALWAYS wait for Ceph ready (Step 4.1) between worker upgrades**
4. **ALWAYS create etcd backup before control plane upgrades**
5. **NEVER hardcode IPs** - query dynamically from cluster
6. **NEVER force upgrades** - if stuck, investigate rather than force
7. **NEVER skip health checks** - even for "quick" upgrades
8. **ALWAYS survey PDBs before worker upgrades** - any PDB stuck at `disruptionsAllowed: 0` makes drain-based upgrades impossible; fall back to `--drain=false` (see Phase 1 and Phase 4)
9. **NEVER leave a worker cordoned across a reboot** - host-pinned Ceph mon and OSD pods cannot reschedule onto a cordoned node, which strands them `Pending` and degrades Ceph. If an upgrade aborted and left a node cordoned, `kubectl uncordon` it immediately
10. **NEVER run `task talos:apply` / `topf apply` between the start of Phase 3 and the completion of Phase 4** - including the gap between the two phases, while nodes straddle versions - `talosctl upgrade` swaps the installer image only and leaves kubelet untouched. Applying machine configs can bump Kubernetes as a side effect. If `topf.yaml`'s `kubernetesVersion` differs from the running kubelet, that drift is deliberate; flag it and stop rather than reconciling it mid-upgrade. Mid-upgrade the cluster also straddles two config contracts, so a single apply would hand different nodes different config forms. The Phase 1 pre-flight apply and the Phase 8 apply (after the pin lands) are the only sanctioned applies
11. **ALWAYS run `task talos:diff` and check it before `TOPF_CONFIRM=false task talos:apply`** - the checked diff replaces the interactive confirmation, so an apply without one is blind

## Timeout Expectations

| Operation                                | Expected Duration | Timeout    |
| ---------------------------------------- | ----------------- | ---------- |
| Node upgrade command                     | 2-5 minutes       | 10 minutes |
| Node Ready after reboot                  | 1-3 minutes       | 5 minutes  |
| etcd rejoin                              | 30-60 seconds     | 2 minutes  |
| Ceph data recovery (PGs `active+clean`)  | 60-90 seconds     | 10 minutes |
| Ceph `HEALTH_OK` (incl. heartbeat decay) | 90s-12 minutes    | 30 minutes |
| Full cluster upgrade                     | 45-90 minutes     | 3 hours    |

**Measured reference (6-node cluster, v1.13.4 to v1.13.9 — a patch upgrade, so no Phase 2b):** control plane nodes took ~4 minutes each with drain enabled. Workers took ~4 minutes each plus Ceph recovery. Ceph data recovery was consistently 60-90 seconds; on one worker the `OSD_SLOW_PING_TIME_*` average then took a further ~10 minutes to decay below threshold while all PGs were already `active+clean`.

## Additional Resources

- [references/discovery.md](references/discovery.md) — topology, schematic and version discovery; the Step 3.1 and Step 3.4 node lookups
- [references/drift-check.md](references/drift-check.md) — Phase 1 pre-flight drift check
- [references/worker-drain.md](references/worker-drain.md) — Phase 1 PDB survey, Step 4.3 `--drain=false`, Step 4.3a recovery
- [references/config-migration.md](references/config-migration.md) — Phase 2b, Steps 2b.1 to 2b.4
- [references/kata.md](references/kata.md) — Step 4.4a Kata config diff, Phase 8 Kata smoke test
- [references/ceph-recovery.md](references/ceph-recovery.md) — Step 4.5 timeline and stale heartbeats, Step 4.5a stale `Error` pods
- [references/rollback.md](references/rollback.md) — control plane and worker rollback
- [references/templates.md](references/templates.md) — issue body, progress comment, blocked reports, completion report, SUCCESS / ROLLBACK / PARTIAL
