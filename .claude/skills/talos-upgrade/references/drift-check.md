# Phase 1: Pre-flight Drift Check

**Pre-flight drift check (before any node changes):** Renovate bumps under `talos/` (for example extraManifests URLs) merge to main without reaching the nodes. Apply them now so Phase 8 shows only this upgrade's changes. `apply` renders from the working tree, so first require `git status --porcelain -- talos/` to be empty; otherwise report PRE-UPGRADE BLOCKED. Then, on an up-to-date main checkout:

```bash
git pull --ff-only
task talos:diff
```

Exit 0 means no drift: continue. Exit 2 means drift; any other non-zero is an error to fix before going on.

If `talosVersion` in `talos/topf.yaml` differs from the running Talos version, the pin already reached main (Renovate or Mergify merged it first). The `machine.install.image` / `installerImage` lines are then expected, not drift. Skip the pre-flight apply, but hold any other drift to the applyable test below: if it passes, record it (with the commits that explain it) in the upgrade issue and leave it for Phase 8, which lists it as expected; if not, report PRE-UPGRADE BLOCKED. Otherwise the running version equals `talosVersion`, no installer-image diff is expected, and the drift is **applyable** only if all hold:

- Every changed line traces to a commit already on main under `talos/` (check `git log` on the changed patch files)
- No Kubernetes version change (that goes through the kubernetes-upgrade skill)
- The dry run reports applying "without a reboot" for every node

If applyable:

```bash
TOPF_CONFIRM=false task talos:apply
task talos:diff    # must exit 0
```

Then re-check nodes Ready, etcd 3/3 and Ceph ready, and record what was applied (commit shas) in the upgrade issue.

If not applyable (drift not explained by main's git history, a Kubernetes version change, or anything needing a reboot), report PRE-UPGRADE BLOCKED with the diff summary.
