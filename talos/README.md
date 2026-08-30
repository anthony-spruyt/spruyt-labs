# Talos Subsystem

## Overview

The Talos subsystem codifies the lifecycle of spruyt-labs Kubernetes machines, from configuration generation with topf through provisioning, maintenance, and recovery activities. This document summarizes operator responsibilities, the supporting assets stored under `talos/`, and the high-level runbook for managing Bossgame E2 control planes, MS-01 workers, and lab VMs. Deep-dive procedures live in
[`docs/machine-lifecycle.md`](docs/machine-lifecycle.md).

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                            | Description                                                                                                                                                                   |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `topf.yaml`                     | topf entrypoint describing cluster identity, node roles, schematic references, and `ref+sops://` pointers into `talenv.sops.yaml`.                                            |
| `schematics/`                   | Image Factory schematic definitions per hardware class, referenced from `topf.yaml` as `@schematics/<class>.yaml`.                                                            |
| `baseconfig/` _(generated)_     | Optional working directory for upstream Talos defaults extracted during new hardware enablement. Typically gitignored.                                                        |
| `bootstrap/` _(generated)_      | Local scratch space for bootstrap artifacts (first control-plane secrets, discovery data). Historically populated by install scripts and retained outside Git for security.   |
| `clusterconfig/` _(gitignored)_ | Inspection output from `task talos:render`, plus the generated `talosconfig`. `topf apply` does not need it - it renders in memory.                                           |
| `docs/`                         | In-repo operations handbook. Includes [`machine-lifecycle.md`](docs/machine-lifecycle.md) for exhaustive runbook details.                                                     |
| `flux/` _(virtual)_             | Flux applies Talos definitions via the `cluster/machines/` kustomization. Flux bootstrap manifests that seed Talos resources are maintained in `talos/helmfile/` (see below). |
| `helmfile/`                     | Helmfile definitions that pin Flux bootstrap components and Talos support charts (e.g., Cilium).                                                                              |
| `legacy/`                       | Historical installation and upgrade scripts retained for reference. Prefer Taskfile automation and documented procedures instead of invoking these scripts directly.          |
| `patches/`                      | Talos patch library. topf merges `all/`, then `<role>/`, then `node/<host>/`, each in lexicographic filename order - see [Patch layering](#patch-layering).                   |
| `scripts/` _(virtual)_          | One-off automation is implemented as Taskfile targets (see `.taskfiles/`). Legacy shell scripts remain in `legacy/` for audit purposes.                                       |
| `secrets/` _(virtual)_          | Age-encrypted Talos secrets (`talenv.sops.yaml`, `talsecret.sops.yaml`) live at the repository root. Access requires the platform Age identity.                               |

<!-- markdownlint-enable MD013 -->

> _Generated or virtual directories may be absent in a clean clone. They will appear locally when running documented tasks._

## Patch layering

topf builds each node's machine config by merging patches in three passes - `all/`, then the node's role directory, then `node/<hostname>/` - and within each directory in lexicographic filename order. That is why every patch carries a numeric prefix.

**The order is load-bearing, so do not renumber files to tidy them up.** Talos concatenates list entries across patches unless the field is tagged `merge:"replace"` in its config machinery (`podSubnets` and `serviceSubnets` are; `machine.udev.rules` is not), and `talosctl` diffs machine config textually. Reordering `machine.udev.rules` changes nothing semantically but still registers as a config
change, and a udev reorder alone turns a reboot-free apply into a reboot.

`patches/shared/` is outside the three merge passes - topf never reads it directly. **A patch that applies to every node belongs in `all/`.** Use `shared/` only when merging first would break ordering, and symlink it from each role directory at the position that preserves that ordering. Today that is one file: the disk scheduler udev rule, which has to land partway down `machine.udev.rules` rather
than at the top.

Two patch formats are in use:

| Extension   | Behaviour                                                                         |
| ----------- | --------------------------------------------------------------------------------- |
| `.yaml`     | Strategic merge patch. SOPS-decrypted, then `ref+` references resolved by `vals`. |
| `.yaml.tpl` | Go template (sprig available). **Skips SOPS and vals entirely.**                  |

A `.tpl` cannot resolve a `ref+sops://` reference. Anything secret that has to be interpolated into a larger string is therefore exposed under `data:` in `topf.yaml` - which is itself resolved through vals - and read from the template as `.Data.<key>`. topf only detects a `ref+` at the start of a value, so a reference buried mid-string is silently left as literal text rather than failing.

> `task talos:render` works offline and uses the `talosVersion` declared in `topf.yaml`. `task talos:apply` asks each node for its **running** version and generates against that version contract. The two agree except during an upgrade window, when a render is not a faithful preview of an apply.

## Optional: Prerequisites

- Use the devcontainer or install the required CLIs (`topf`, `vals`, `talosctl`, `kubectl`, `flux`, `task`, `age`, `sops`).

- Possess the Age identity that decrypts Talos secrets.

- Maintain the shared hardware inventory (serials, VLANs, rack locations) before onboarding nodes.

- Confirm Flux controllers are healthy:

  ```bash
  flux get kustomizations -n flux-system
  ```

## Operation

### Summary

Platform engineering owns the Talos lifecycle. Operators provision control-plane and worker nodes, drive GitOps workflows for machine configuration, and coordinate maintenance or recovery actions. Comprehensive procedures are documented in [`docs/machine-lifecycle.md`](docs/machine-lifecycle.md) and [`MAINTENANCE.md`](MAINTENANCE.md); this readme highlights the key phases.

### Preconditions

- Tooling and secrets access validated as described above.
- Latest `main` branch merged, working from a clean feature branch.
- Out-of-band access (BMC or hypervisor console) available for each node.
- For storage maintenance, ensure Ceph dashboards are accessible and current.

### Procedure

#### Provision new hardware or VMs

1. Add the node to `topf.yaml`, create `patches/node/<hostname>/` for anything unique to it (install disk, addressing), and update overlay snippets under `cluster/machines/`.

2. Render the config for inspection:

   ```bash
   task talos:render
   ```

   Outputs land in `talos/clusterconfig/topf/`.

3. **Secrets** – The bundle in `talsecret.sops.yaml` is reused as-is. Refresh the local client credentials when necessary:

   ```bash
   task talos:talosconfig
   ```

4. Boot the host with the appropriate SecureBoot ISO (see [Talos image schematics](#talos-image-schematics)).

5. Apply configs once the Talos API responds:

   ```bash
   task talos:apply NODE=<hostname>
   ```

   `NODE` is a Go regex over the hosts in `topf.yaml`; omit it to target every node. The Task UI cannot pass variables, so `talos:apply-c1` … `talos:apply-w3` exist as clickable per-node equivalents.

6. Bootstrap the first control-plane node with `talosctl bootstrap`.

Detailed provisioning guidance lives in [`docs/machine-lifecycle.md`](docs/machine-lifecycle.md#provisioning-new-hardware-or-vms).

#### GitOps update flow

1. Branch from `main`:

   ```bash
   git checkout -b feat/talos-<change>
   ```

2. Modify overlays and `talos/patches/*` as required.

3. Render diffs without secrets:

   ```bash
   task talos:diff
   ```

4. Run validation:

   ```bash
   task validate
   task dev-env:lint
   ```

5. Commit with lifecycle context and open a PR.

6. After merge, expedite rollout:

   ```bash
   flux reconcile kustomization cluster-machines --with-source
   ```

7. Confirm nodes adopted the change:

   ```bash
   talosctl -n <node-ip> get machineconfig -o yaml
   ```

#### Node pool management

- **Control plane** – Maintain an odd member count for etcd quorum. Taints/labels must remain in place:

  ```bash
  kubectl label node <host> node-role.kubernetes.io/control-plane=
  kubectl taint node <host> node-role.kubernetes.io/control-plane=:NoSchedule
  ```

- **Workers** – Group nodes by hardware class using labels such as `node.kubernetes.io/instance-type` or `topology.spruyt-labs.io/rack`. Apply workload taints declaratively in overlays.

- **Scaling** – Temporary capacity can be provided by VM overlays; remove the overlay and reconcile to decommission.

#### Maintenance

- **SecureBoot schematic selection**

  - Browse `https://factory.talos.dev/installer/?options=secureboot:<true|false>` and choose the schematic matching the node's hardware profile.
  - Confirm SecureBoot alignment (`secureboot:1` for SecureBoot-enabled nodes, `secureboot:0` otherwise). Copy the Factory installer image digest.

- **Upgrade command template**

  ```sh
  talosctl upgrade \
    --nodes <node-ip> \
    --endpoints <control-plane-endpoint> \
    --image factory.talos.dev/metal-installer-secureboot/<schematic>:<version>
  ```

  - Upgrade control plane nodes first, one at a time.
  - Proceed with workers after the control plane is stable.

- **Verification checklist**

  - `talosctl version --nodes <node-ip> --endpoints <control-plane-endpoint>`
  - `kubectl get nodes` (expect all `Ready`, correct Talos/K8s versions)
  - `flux get kustomizations` (ensure GitOps sync status is `Ready`)
  - `talosctl ... etcd status` for control plane health confirmation

##### Kubernetes control-plane upgrade

> Reference: [Sidero Labs guide](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/upgrading-kubernetes)

1. Confirm cluster prerequisites: Flux controllers report `Ready`, recent etcd snapshots are archived, Talos nodes run a supported release, and the maintenance window is approved.

2. Perform a dry run to surface API deprecations and preview the upgrade plan:

   ```bash
   talosctl --nodes {CP_IP} upgrade-k8s --to v1.36.4 --dry-run
   ```

   - Replace `{CP_IP}` with the control-plane node you are validating.
   - Resolve warnings about deprecated resources or missing manifests before continuing.

3. Execute the upgrade after the dry run succeeds:

   ```bash
   talosctl --nodes {CP_IP} upgrade-k8s --to v1.36.4
   ```

   - Talos orchestrates control-plane members sequentially and updates kube-proxy/kubelet while `--upgrade-kubelet` remains enabled (default).
   - Include `--endpoint <control-plane-endpoint>` when invoking the command through the VIP, or disable kubelet upgrades per node with `--upgrade-kubelet=false`.

4. Validate cluster state when the command finishes:

   - `kubectl version --short`
   - `kubectl get nodes`
   - `talosctl health --nodes <node-ip>`
   - `flux get kustomizations -n flux-system`

5. Confirm worker nodes report the expected kubelet version (if upgraded) or schedule drains and restarts when kubelet updates were deferred. Archive the dry-run output and validation notes with the change record.

#### Rollback and disaster recovery

- Revert offending commits and force Flux reconciliation.
- Reapply last-known-good configs from `talos/clusterconfig/`.
- Restore etcd snapshots with `talosctl etcd snapshot restore` when quorum is lost.
- Rehydrate secrets from SOPS backups and rotate Age identities if compromise is suspected.
- Rebuild nodes (wipe, reinstall, reapply) when disks or hardware fail. Sequence recovery: control plane → storage workers → remaining pools.

### Validation

- `talosctl health` – global Talos API health.

- `task talos:diff` – detect config drift.

- `kubectl get nodes -o wide` and `kubectl describe node <host>` – kubelet state, labels, taints.

- `flux get kustomizations cluster-machines -n flux-system` – GitOps status.

- `talosctl version -n <node-ip>` – OS version confirmation post-upgrade.

- Storage validation:

  ```bash
  kubectl -n rook-ceph get pods
  ceph status
  ```

### Troubleshooting

#### Node reports `NotReady`

```bash
kubectl describe node <host>
talosctl logs -n <node-ip> kubelet
talosctl logs -n <node-ip> containerd
talosctl get staticpod kube-system/cilium -n <node-ip>
```

#### Talos API unreachable

```bash
talosctl health --nodes <node-ip>
talosctl -n <node-ip> get machineconfig
```

Compare active NIC configuration with the overlay. Use the BMC or hypervisor console if remediation requires manual intervention.

#### Storage integration issues

```bash
talosctl -n <node-ip> ls /dev/disk/by-id
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

Confirm Ceph OSD placement labels and ensure encrypted volumes unlocked correctly.

#### Machineconfig drift

```bash
task talos:diff
talosctl -n <node-ip> get appliedconfiguration
task talos:apply NODE=<hostname>
```

Refresh local client credentials with `task talos:talosconfig` if drift stems from a credential mismatch.

#### Diagnostic command quick reference

| Target                | Command                             |
| --------------------- | ----------------------------------- |
| Kernel logs           | `talosctl -n <node-ip> dmesg`       |
| Talos services        | `talosctl -n <node-ip> logs`        |
| Kubernetes components | `talosctl -n <node-ip> logs -k`     |
| etcd                  | `talosctl -n <node-ip> logs etcd`   |
| Privileged pod shell  | `task dev-env:priv-pod node=<node>` |

### Escalation

- Post incidents in the platform on-call channel with Talos logs, Flux status, recent commit hashes, and remediation attempts.
- Engage hardware owners for physical faults or BMC access issues.
- Coordinate with the storage lead when Ceph flags remain set or OSDs fail to recover.
- Escalate to security for Age identity rotation or secrets compromise.

## Talos Image Schematics

<!-- markdownlint-disable MD013 -->

| Hardware class            | Schematic ID                                                       | SecureBoot ISO                                                                                                                                  | Upgrade image                                                                                                           |
| ------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Bossgame E2 control plane | `9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d` | [Download](https://factory.talos.dev/image/9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d/v1.13.9/metal-amd64-secureboot.iso) | `factory.talos.dev/metal-installer-secureboot/9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d:v1.13.9` |

Your image schematic ID is: `9245f77a34e6874d7aa65cad39741cfa32a663c95251eeecb529853b81ab3d2d`

```yaml
customization:
  extraKernelArgs:
    - -lockdown
    - lockdown=integrity
    - quiet
    - loglevel=3
    - amd_pstate=1
    - pcie_aspm=off
    - pci=pcie_bus_perf
    - nvme_core.default_ps_maxlatency_us=0
    - iommu=pt
    - idle=nomwait
  systemExtensions:
    officialExtensions:
      - siderolabs/amd-ucode
      - siderolabs/iscsi-tools
      - siderolabs/lldpd
      - siderolabs/nvme-cli
      - siderolabs/util-linux-tools
```

| MS-01 worker | `1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1` | [Download](https://factory.talos.dev/image/1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1/v1.13.9/metal-amd64-secureboot.iso) | `factory.talos.dev/metal-installer-secureboot/1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1:v1.13.9` |

Your image schematic ID is: `1405ea9d3df696997aab915b3f992117ef0f1121ef7b1674b77c3589f13424d1`

```yaml
customization:
  extraKernelArgs:
    - -lockdown
    - lockdown=integrity
    - quiet
    - loglevel=3
    - intel_iommu=on
    - iommu=pt
    - net.ifnames=0
  systemExtensions:
    officialExtensions:
      - siderolabs/i915
      - siderolabs/intel-ucode
      - siderolabs/kata-containers
      - siderolabs/lldpd
      - siderolabs/thunderbolt
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
```

<!-- markdownlint-enable MD013 -->

Additional asset: SecureBoot UKI – <https://factory.talos.dev/image/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb/v1.13.9/metal-amd64-secureboot-uki.efi>

## References

- Repository runbook standards – [`README.md`](../README.md#runbook-standards)
- Machine lifecycle deep dive – [`docs/machine-lifecycle.md`](docs/machine-lifecycle.md)
- Flux GitOps workflows – [`cluster/flux/README.md`](../cluster/flux/README.md)
- Application runbooks – [`cluster/apps/README.md`](../cluster/apps/README.md)
- Talos upstream documentation – <https://www.talos.dev/>
- topf project – <https://github.com/postfinance/topf>
- FluxCD documentation – <https://fluxcd.io/>
- Ceph maintenance reference – <https://rook.io/docs/rook/latest/>
