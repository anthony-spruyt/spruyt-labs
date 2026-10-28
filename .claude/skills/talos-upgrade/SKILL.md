---
name: talos-upgrade
description: >
  Use when a Renovate PR bumps talosVersion in talos/topf.yaml, the user asks to upgrade Talos OS across the cluster,
  planned maintenance needs node upgrades, or a post-incident rebuild moves nodes to a newer Talos version. Upgrades one
  node at a time. Not for Kubernetes-only upgrades (use kubernetes-upgrade), config changes without a version bump, or
  single-node troubleshooting (use talosctl directly). Not for subagents.
argument-hint: <target-version>
---

# Talos Upgrade

Safely upgrade Talos OS across the cluster while preserving etcd quorum (control plane) and Ceph data availability (workers). Cluster stability is paramount. Control plane nodes go first, one at a time (3 CP nodes = need 2 healthy minimum), then workers, one at a time with a Ceph gate between each. Patch upgrades swap the installer image; minor upgrades also migrate machine config to new document types.

Main session only: it runs qa-validator, reviewers and chore-runners, and talks to the owner itself.

**Read each phase's reference file when you start that phase, and re-read the current one after a compaction.**

Keep `$` plus a digit out of this file: it is an argument placeholder, even in code fences.

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

## Standing Rules

- **Landing rule:** land changes on main per the `orchestration` skill: commit in a `workspace.sh` clone, staged by name, with `Ref #<issue>`; qa-validator with the issue number and the changed files (`./lint.sh` where `.claude/rules/validation.md` skips it, as for `talos/README.md`); a fresh reviewer READY; `push-reviewed.sh`. Then `git pull --ff-only` in the checkout that runs `task talos:*`.
- **Clean-checkout gate:** in that checkout, run `git pull --ff-only`; `git status --porcelain -- talos/` must print nothing and `git rev-parse HEAD` must equal `git rev-parse origin/main`. `apply` renders from the working tree, so if either fails, stop and land the change first.
- **Issue:** track the upgrade in an issue; if none exists, create it per "Issue body" in [references/templates.md](references/templates.md). Plain lists, not checkboxes (hard to edit reliably), in the body; per-node progress as comments; edit the body when the plan changes.
- **No IPs in the issue:** name nodes by hostname in every issue comment, and strip IPs and network details from any command output posted there (`talosctl etcd status` and talosctl dial errors print node IPs).
- **Troubleshooting:** look an unexpected Talos, etcd or Ceph error up in Context7 (`/siderolabs/talos`, `/rook/rook`) before improvising a fix. Durations and timeouts: [references/timeouts.md](references/timeouts.md).

## Upgrade Workflow

### Phase 0: Input Validation and Upgrade Classification

1. Get current and target versions (Renovate PR or user request, and `talos/topf.yaml`: "Version Detection" in [references/discovery.md](references/discovery.md)); validate the format (vX.Y.Z).
2. Classify the upgrade. This decides whether Phase 2b runs and how Critical Safety Rule 10 applies:

| Classification | Example            | Config migration                                |
| -------------- | ------------------ | ----------------------------------------------- |
| Patch          | v1.13.4 to v1.13.9 | None. Image swap only, skip Phase 2b            |
| Minor          | v1.13.9 to v1.14.0 | Required. Run Phase 2b before touching any node |
| Major          | v1.x to v2.x       | Stop and tell the owner it needs a manual plan  |

3. For a minor upgrade, first read the release notes (`gh release view <target-version> --repo siderolabs/talos --json body -q .body`): new config documents emitted by default, v1alpha1 fields deprecated or moved, the Kubernetes version shipped.
4. `kubernetesVersion` in `talos/topf.yaml` is pinned apart from `talosVersion`, and a minor Talos release can drop an older kubelet: stop if the pin falls outside the release notes' component list and supported-versions range.

### Phase 1: Pre-Upgrade Validation

Read [references/pre-upgrade.md](references/pre-upgrade.md) now for Groups 1 to 3 and the installer images. **Run ALL checks. BLOCK if any fail.**

- **Group 4, PDB survey (do NOT skip):** [references/worker-drain.md](references/worker-drain.md). A CNPG primary-role PDB means `--drain=false` in Phase 4; `rook-ceph-osd-host-<node>` is expected; `rook-ceph-mon-pdb` at `ALLOWED 0` means a mon is already down: STOP, investigate first
- **Pre-flight drift check (before any node changes):** pass the clean-checkout gate first, then [references/drift-check.md](references/drift-check.md). If the pin already reached main, skip the apply and record applyable drift for Phase 8; otherwise apply only **applyable** drift. Anything else: PRE-UPGRADE BLOCKED

**Pre-upgrade checklist (all must pass):**

- [ ] All nodes report Ready in kubectl
- [ ] talosctl health passes
- [ ] etcd has 3 healthy members with consistent terms
- [ ] Ceph ready (see Step 4.1)
- [ ] GPU baseline: every ms-01 passes the Step 4.4b gate ([references/workers.md](references/workers.md)) before any node is touched
- [ ] All Flux kustomizations are Ready
- [ ] No pending HelmRelease upgrades/failures
- [ ] PDBs surveyed and worker drain strategy chosen
- [ ] Target installer images verified to exist for BOTH schematics
- [ ] No unapplied drift between `talos/` on main and the nodes, or it was applied (see pre-flight drift check)

**If ANY check fails, STOP and tell the owner** with the PRE-UPGRADE BLOCKED report ([references/templates.md](references/templates.md)).

### Phase 2: etcd Backup

Before any control plane upgrade, stream an etcd snapshot to this machine (Phase 2 in [references/control-plane.md](references/control-plane.md)) and post the confirmation, with the local snapshot path, to the issue.

### Phase 2b: Config Migration (minor upgrades only)

Skip for patch upgrades. A new minor's config documents collide with old `v1alpha1` fields, so migrate before any node is touched. Read [references/config-migration.md](references/config-migration.md) now:

- **Step 2b.1:** set the target `talosVersion`, `task talos:render`, then restore `talosVersion` and revert the SOPS side effects
- **Step 2b.2:** `talosctl validate` every node against the target contract; a clean render can still be invalid
- **Step 2b.3:** land the migration (landing rule), then confirm `task talos:diff` is empty. **Do not begin Phase 3 with an unmerged migration.**
- **Step 2b.4:** the migrated documents reach the nodes in the Phase 8 apply, not before

### Phase 3: Control Plane Upgrades (Sequential)

Pass the clean-checkout gate first. Read [references/control-plane.md](references/control-plane.md) now. One node at a time: two down at once loses etcd quorum. For EACH control plane node:

- **Step 3.1:** CP node IPs, and the schematic from the live control plane node
- **Step 3.2:** etcd must show 3 healthy members
- **Step 3.3:** upgrade with a **surviving CP node as endpoint, NOT the cluster VIP**, which may route to the node being upgraded
- **Step 3.4:** node Ready (5 minutes), Talos API up, etcd 3 healthy: consistent `RAFT INDEX`, empty `ERRORS`, a **stable** term (one bump after upgrading the leader is normal; a climbing term means flapping: stop)
- **Step 3.5:** `talosctl version` shows the target version on the node
- **Step 3.6:** post progress to the issue

**WAIT between each control plane node:** minimum 60 seconds after node Ready, etcd 3 healthy, node fully Ready.

### Phase 4: Worker Upgrades (Sequential with Ceph Safety)

One at a time, Ceph gate between each: two workers down can leave PGs without a replica. Read [references/workers.md](references/workers.md) now. For EACH worker node:

**Step 4.1: Pre-node Ceph check (BLOCKING).** **Ceph ready** means all OSDs up and in, all PGs `active+clean`, mons in quorum, and health is either `HEALTH_OK` or `HEALTH_WARN` whose only checks are `OSD_SLOW_PING_TIME_BACK` / `OSD_SLOW_PING_TIME_FRONT` (stale reboot heartbeats, see Step 4.5) or `BLUESTORE_SLOW_OP_ALERT` (note it; do not restart OSDs to clear it). Any other warning, any `HEALTH_ERR` or live `SLOW_OPS` is not ready: stop and tell the owner with the WORKER UPGRADE BLOCKED report ([references/templates.md](references/templates.md)).

- **Step 4.2:** worker IPs, and the schematic from a live worker ([Schematic Discovery](references/discovery.md#schematic-discovery))
- **Step 4.3:** default drain if the Phase 1 survey was clean; `--drain=false` only if it found a PDB stuck at `disruptionsAllowed: 0`, after reading Step 4.3 in [references/worker-drain.md](references/worker-drain.md). **Do NOT manually cordon the node as a substitute** (rule 9)
- **Step 4.3a:** a drain-based upgrade aborted and left the node cordoned: `kubectl uncordon <hostname>` first, and confirm the node was NOT upgraded before retrying with `--drain=false` (worker-drain.md)
- **Step 4.4:** node Ready (5 minutes), Talos API responsive
- **Step 4.4a (first worker only):** run the Kata config diff in [references/kata.md](references/kata.md). If it shows more than the expected differences, fix `talos/patches/worker/13-tune-kata-memory.yaml` as that file says, land it (landing rule) before Phase 8, and carry on. Do not apply it now (rule 10)
- **Step 4.4b (each ms-01, BLOCKING):** GPU gate in [references/workers.md](references/workers.md): `gpu.intel.com/i915` allocatable is 2 and a one-shot pod pinned to the node lists OpenVINO `GPU`. A failed gate: stop and tell the owner with the WORKER UPGRADE BLOCKED report ([references/templates.md](references/templates.md)), even on the last worker. Later drains or the Phase 6 rebalance would push scanner pods onto a node without a working GPU. No CPU fallback
- **Step 4.5:** poll until Ceph ready (Step 4.1), timeout 30 minutes; judge by data state, and wait rather than restart an OSD ([references/ceph-recovery.md](references/ceph-recovery.md))
- **Step 4.5a:** `Error` pods after a reboot are stale; leave them and judge health from controllers (ceph-recovery.md)
- **Step 4.6:** post progress to the issue, including Ceph recovery time

### Phase 5: Post-Upgrade Validation

Run ALL checks in [references/post-upgrade.md](references/post-upgrade.md) to confirm the upgrade, then clean up stale Ceph heartbeats per Step 4.5.

### Phase 6: Workload Rebalancing (Optional)

Once all nodes are upgraded and Ceph is healthy, trigger a manual descheduler run (post-upgrade.md). Skip it if distribution already looks balanced.

### Phase 7: Update talos/README.md

Update the Talos version, and any changed schematic ID, in `talos/README.md` "Talos Image Schematics" on main, not in a separate docs PR (Phase 7 in [references/post-upgrade.md](references/post-upgrade.md)). Land only `talos/README.md` (landing rule).

### Phase 8: Land the Pin and Apply Machine Config

Read [references/apply.md](references/apply.md) now. **The pin must be on main first**, or the apply puts every node back on the old installer image:

- **Renovate PR:** have a `chore-runner` wait for its CI (brief: `--repo <owner/repo>` and the PR number); merge with `gh pr merge <N> --squash` only once CI is green
- **Manual request:** set `talosVersion` in `talos/topf.yaml` and land it (landing rule)

Pass the clean-checkout gate, then run `task talos:diff`. Expected diff:

- **Patch upgrade:** only `machine.install.image` → `<schematic>:<new-version>` on each node
- **Minor upgrade:** the installer image, plus the migrated documents from Phase 2b
- **Kata config fixed in Step 4.4a:** the `kata-containers/configuration.toml` file on the workers
- **Pin merged before Phase 1:** the non-installer drift recorded in Phase 1, each line traced to a commit under `talos/` on main

Anything else, such as a Kubernetes version change or unrelated patch drift: stop and report it. Do not apply.

Apply with `TOPF_CONFIRM=false task talos:apply`; `task talos:diff` must then exit 0. Re-check node Ready, etcd 3/3 and Ceph ready (Step 4.1). For a minor upgrade, verify authentication, kubelet settings and node labels (Step 2b.4). Smoke-test Kata ([references/kata.md](references/kata.md)); on failure, fix and land the patch, then repeat the gate, diff and apply.

If you can't finish this phase in the session (for example the pin isn't on main yet), report PARTIAL, not SUCCESS, with land-pin → diff → apply as the required actions.

### Phase 9: Final Report

1. If the pin PR touched `cluster/`, run cluster-validator per `.claude/rules/validation.md` with the upgrade issue number and the range from the last validated `origin/main` sha (the start of the first range `push-reviewed.sh` printed in this run, else `origin/main` before the pin merged) to `origin/main`.
2. Post the completion report ("Upgrade Complete" in [references/templates.md](references/templates.md)) to the issue.
3. Close the tracking issue after cluster-validator confirms, or once the report is posted if it didn't need to run.

## Outcome

Tell the owner the outcome with the SUCCESS, ROLLBACK or PARTIAL template in [references/templates.md](references/templates.md). Post ROLLBACK and PARTIAL to the issue too; for SUCCESS, the Phase 9 completion report is the issue comment. SUCCESS requires Phase 8 done: pin on main, apply run, clean diff. Otherwise report PARTIAL.

## Rollback Procedures

Downgrades for a failed node, and checks for Ceph still degraded after a worker recovers: [references/rollback.md](references/rollback.md).

**If etcd quorum is lost (< 2 healthy members):** stop and report ROLLBACK to the owner. The owner runs the recovery from `docs/disaster-recovery.md` with the Phase 2 snapshot; do not run it yourself.
