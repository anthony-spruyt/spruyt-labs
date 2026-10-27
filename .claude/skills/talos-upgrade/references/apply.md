# Phase 8: Land the Pin and Apply Machine Config

`talosctl upgrade` only swaps the running image. The machine config on each node still carries the old `machine.install.image`, and for minor upgrades the old config documents. Run `task talos:apply` to bring it in line with the repo. Skipping this leaves the nodes drifted from `talos/topf.yaml`.

**The pin must be on main first.** `apply` renders `machine.install.image` from `talosVersion` in `talos/topf.yaml`. If you apply before the pin moves, every node goes back to the old installer image.

## Diff

Once the pin is on main and pulled locally, and the clean-checkout gate passes, run the dry run. It's non-interactive and safe:

```bash
git pull --ff-only
task talos:diff    # exits non-zero when there is drift - that is the expected result here
```

The expected diff is listed in the skill. Pre-existing drift was already applied in Phase 1 (or recorded there, if the pin was already on main), so anything else, such as a Kubernetes version change or unrelated patch drift, means stop and report it. Do not apply.

## Apply

Apply it yourself. `topf` asks a `[y/n]` question per node on stdin; the diff you just checked is that confirmation, so turn the prompt off:

```bash
TOPF_CONFIRM=false task talos:apply
```

Then re-run `task talos:diff`. It must exit 0 (no drift). Re-check node Ready, etcd 3/3 and Ceph ready (Step 4.1), because an apply can restart services.

For a minor upgrade, check what the migrated documents changed, as Step 2b.4 in [config-migration.md](config-migration.md) says: authentication, kubelet settings and node labels.

Then run the Kata smoke test in [kata.md](kata.md).
