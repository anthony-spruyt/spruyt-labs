# Talos

## Overview

Machine config for the six Talos nodes, generated with [topf](https://github.com/postfinance/topf). Talos config is **not** reconciled by Flux: a merged change does nothing until someone runs `task talos:apply`.

Procedures live in the runbooks:

| Task                                       | Runbook                                                   |
| ------------------------------------------ | --------------------------------------------------------- |
| First build (Talos, Cilium, Flux)          | [docs/bootstrap.md](../docs/bootstrap.md)                 |
| Config changes, reboots, Talos/K8s upgrade | [docs/maintenance.md](../docs/maintenance.md)             |
| Replace a node, restore etcd               | [docs/disaster-recovery.md](../docs/disaster-recovery.md) |

## Layout

| Path                  | Contents                                                                                                                                    |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `topf.yaml`           | Cluster identity, versions, node list and schematic per node. Addresses and endpoints are `ref+sops://` references into `talenv.sops.yaml`. |
| `talenv.sops.yaml`    | The values `topf.yaml` references: node addresses, cluster name, API endpoint. Edit with `sops talos/talenv.sops.yaml`.                     |
| `talsecret.sops.yaml` | The cluster PKI bundle. Reused as-is; never regenerate it on a running cluster.                                                             |
| `patches/`            | Machine config patches - see [Patch layering](#patch-layering).                                                                             |
| `schematics/`         | Image Factory schematic per hardware class - see [Talos Image Schematics](#talos-image-schematics).                                         |
| `helmfile/`           | Bootstrap-only installs of Cilium and Flux, used before Flux exists. Chart versions are read from the manifests under `cluster/`.           |
| `clusterconfig/`      | Gitignored. `task talos:render` output and the generated `talosconfig`. `task talos:apply` does not read it; it renders in memory.          |

## Patch layering

topf builds each node's machine config by merging patches in three passes - `all/`, then the node's role directory, then `node/<hostname>/` - and within each directory in lexicographic filename order. That is why every patch carries a numeric prefix.

**The order is load-bearing, so do not renumber files to tidy them up.** Talos concatenates list entries across patches unless the field is tagged `merge:"replace"` in its config machinery (`podSubnets` and `serviceSubnets` are; `UdevRulesConfig` `rules` is not), and `talosctl` diffs machine config textually. Reordering udev rules changes nothing semantically but still shows up as drift in
`task talos:diff` on every affected node.

`patches/shared/` is outside the three merge passes - topf never reads it directly. **A patch that applies to every node belongs in `all/`.** Use `shared/` only when merging first would break ordering, and symlink it from each role directory at the position that preserves that ordering. Today that is one file: the disk scheduler udev rule, which has to land partway down the merged
`UdevRulesConfig` rules list rather than at the top.

`UdevRulesConfig` has no `name`, so topf merges every patch's document into one per node, in patch order. Once that document exists Talos ignores `machine.udev` without a validation error, so add udev rules only as `UdevRulesConfig`.

Two patch formats are in use:

| Extension   | Behaviour                                                                         |
| ----------- | --------------------------------------------------------------------------------- |
| `.yaml`     | Strategic merge patch. SOPS-decrypted, then `ref+` references resolved by `vals`. |
| `.yaml.tpl` | Go template (sprig available). **Skips SOPS and vals entirely.**                  |

A `.tpl` cannot resolve a `ref+sops://` reference. Anything secret that has to be interpolated into a larger string is therefore exposed under `data:` in `topf.yaml` - which is itself resolved through vals - and read from the template as `.Data.<key>`. topf only detects a `ref+` at the start of a value, so a reference buried mid-string is silently left as literal text rather than failing.

## Tasks

`task --list` describes each `talos:*` task. What the descriptions do not say:

- All of them need `SOPS_AGE_KEY_FILE`, and they refuse to run unless `topf`, `sops` and `vals` are on `PATH`. Without `sops`, topf falls back to writing the PKI bundle in plaintext.
- `NODE` is a Go regex matched against the `host` values in `topf.yaml`. Anchor it (`NODE='^ms-01-1$'`) when you mean one node. The Task UI cannot pass variables, so `talos:apply-c1` ... `talos:apply-w3` are per-node equivalents.
- `task talos:diff` exits non-zero when it finds drift. That means drift, not a broken command.
- `task talos:render` works offline and uses the `talosVersion` declared in `topf.yaml`. `task talos:apply` and `task talos:diff` ask each node for its **running** version and generate against that version contract. The two agree except during an upgrade window, when a render is not a faithful preview of an apply.

## Upgrade and reboot notes

The upgrade procedure is in [maintenance.md](../docs/maintenance.md#talos-os-upgrade). Background it relies on:

- **CNPG sets `enablePDB: false` on purpose.** With it removed, the operator creates a PDB with `minAvailable: 1` that selects only the primary pod, so `disruptionsAllowed` is always `0` whatever the instance count. `talosctl upgrade` drains by default, waits on that PDB and aborts. Raising `--drain-timeout` does not help.
- **`--drain=false` is safe here.** Kubelet graceful shutdown (`shutdownGracePeriod` in `patches/all/06-configure-kubelet.yaml.tpl`) still sends pods SIGTERM and waits their grace period during the reboot.
- **`OSD_SLOW_PING_TIME_BACK` / `_FRONT` after a worker reboot are harmless.** They are a decaying average of ping times sampled during the reboot and can take about 10 minutes to clear after all PGs are `active+clean`. Keep waiting while the millisecond value falls; only restart the OSD if it stays flat for several minutes.
- **Pods in `Error` after a reboot** are objects left over from the previous boot and are garbage collected. Judge health by controller ready replicas, not pod phase.

## Adding a node

Replacing hardware under an existing hostname is in [disaster-recovery.md](../docs/disaster-recovery.md#replace-a-node). For a new hostname:

1. Add the node's address to `talenv.sops.yaml` (`sops talos/talenv.sops.yaml`), then a `nodes:` entry in `topf.yaml` with `host`, `ip` (as a `ref+sops://` reference), `role` and `schematicId`.

2. Create `patches/node/<hostname>/` by copying a node of the same role, and set the install disk serial in `01-configure-install-disk.yaml`. Read serials with `talosctl -n <node-ip> get disks --insecure` while the node is in maintenance mode.

3. Workers: add the Ceph disk to `devicePathFilter` in [`rook-ceph-cluster/app/values.yaml`](../cluster/apps/rook-ceph/rook-ceph-cluster/app/values.yaml). The Thunderbolt ring is wired for exactly three workers ([rook-ceph-cluster/README.md](../cluster/apps/rook-ceph/rook-ceph-cluster/README.md)).

4. Control planes: keep an odd count for etcd quorum, and check `data.machineCertSans` / `data.apiServerCertSans` in `topf.yaml`. Append to those lists; reordering them shows up as a diff on every node.

5. Add per-node entries to `.taskfiles/talos/tasks.yaml` and `.taskfiles/dev-env/tasks.yaml` if you want Task UI shortcuts.

6. Boot the node from its class's SecureBoot ISO and apply:

   ```bash
   task talos:apply NODE='^<hostname>$'
   ```

   **Verify:** `kubectl get nodes` shows it `Ready`, and `task talos:diff` exits 0.

## Talos Image Schematics

Schematic definitions live in [`schematics/`](schematics/). Resolve an ID with `curl -sX POST --data-binary @talos/schematics/<class>.yaml https://factory.talos.dev/schematics`, or print the IDs in use with `task talos:schematic-ids`. The running installer image is on every node: `kubectl get node <node-name> -o jsonpath='{.metadata.annotations.installerImage}'`.

Update this table when a Talos upgrade or schematic change lands ([maintenance.md](../docs/maintenance.md#talos-os-upgrade)).

<!-- markdownlint-disable MD013 -->

| Hardware class            | Definition                            | Schematic ID                                                       | SecureBoot assets                                                                                                                                                                                                                                                                           | Upgrade image                                                                                                           |
| ------------------------- | ------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Bossgame E2 control plane | [`e2.yaml`](schematics/e2.yaml)       | `9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d` | [ISO](https://factory.talos.dev/image/9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d/v1.14.1/metal-amd64-secureboot.iso) · [UKI](https://factory.talos.dev/image/9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d/v1.14.1/metal-amd64-secureboot-uki.efi) | `factory.talos.dev/metal-installer-secureboot/9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d:v1.14.1` |
| MS-01 worker              | [`ms-01.yaml`](schematics/ms-01.yaml) | `1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1` | [ISO](https://factory.talos.dev/image/1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1/v1.14.1/metal-amd64-secureboot.iso) · [UKI](https://factory.talos.dev/image/1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1/v1.14.1/metal-amd64-secureboot-uki.efi) | `factory.talos.dev/metal-installer-secureboot/1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1:v1.14.1` |

<!-- markdownlint-enable MD013 -->

## References

- [topf documentation](https://github.com/postfinance/topf/tree/main/docs)
- [Talos documentation](https://docs.siderolabs.com/talos/)
