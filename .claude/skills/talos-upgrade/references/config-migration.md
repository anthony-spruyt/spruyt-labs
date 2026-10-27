# Phase 2b: Config Migration (minor upgrades only)

Skip entirely for patch upgrades. For a minor upgrade the machine config has to be migrated before any node is touched, because a new Talos minor introduces config documents that the old `v1alpha1` fields collide with.

**Render and apply do not use the same version contract.** `task talos:render` generates against `talosVersion` in `topf.yaml`. `task talos:apply` asks each node for its **running** version and generates against that contract. During an upgrade window the two disagree, so a clean render is not evidence that an apply will succeed. Gate patches on the node's version with a guard such as `{{- if semverCompare ">=X.Y.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}`, so one patch set serves both contracts.

## Step 2b.1: Render against the target contract

Set `talosVersion: <target-version>` in `talos/topf.yaml`, then:

```bash
task talos:render
```

A render failure here names the patch and the path that broke. Fix it before continuing.

Restore `talosVersion` afterwards — the pin moves in Phase 8, not now. `topf render` also rewrites the two SOPS files in `talos/` as a side effect; revert them without naming them, since hooks block that: `git diff --name-only -- talos | grep -F '.sops.' | xargs -r git checkout --`.

## Step 2b.2: Validate against the target contract

`topf render` does not run `V1Alpha1ConflictValidate`, so a clean render can still be an invalid config. Validation is what catches a `v1alpha1` field colliding with its replacement document.

```bash
talosctl validate --config talos/clusterconfig/topf/<node>.yaml --mode metal
```

Every node must validate. A conflict error names both the v1alpha1 path and the document that supersedes it — migrate the offending patch to the new document, then re-render and re-validate.

## Step 2b.3: Land the migration on main before upgrading

Do not begin Phase 3 with an unmerged migration — a node that reboots into the new version generates against the new contract and needs the migrated patches already on main. Land the changed patch files by the landing rule in the skill. Then, in the checkout that runs `task talos:*`, now pulled to the new `origin/main`, run the diff below.

**The new documents cannot be applied yet, and that is expected.** `apply` generates against each node's running version, so while every node is still on the old release the guards take their old-version branch and `topf apply` emits the *old* config form. The migrated documents only reach a node after that node is running the new version. With the pin still on the old version, the diff should be empty:

```bash
task talos:diff
```

Any drift means a guard is keyed wrong and would push new-version documents at an old-version node; fix the guard and re-diff. There is nothing to apply here.

## Step 2b.4: Apply the migrated config after the nodes are upgraded

This is the Phase 8 apply. Only once every node reports the new version does `apply` generate the new documents, so the Phase 8 diff shows them. Anything whose behaviour is expressed through a migrated document — authentication, kubelet settings, node labels — changes there, not in Phase 2b.3. Verify those specifically rather than assuming the upgrade covered them.

Once this apply is healthy the old-version template branches are dead code. Removing them is follow-up work, not part of the upgrade.
