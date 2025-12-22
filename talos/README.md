# Talos Subsystem

## Overview

The Talos subsystem codifies the lifecycle of spruyt-labs Kubernetes machines,
from configuration generation with Talhelper through provisioning, maintenance,
and recovery activities. This document summarizes operator responsibilities, the
supporting assets stored under `talos/`, and the high-level runbook for managing
Bossgame E2 control planes, MS-01 workers, and lab VMs. Deep-dive procedures
live in [`docs/machine-lifecycle.md`](docs/machine-lifecycle.md).

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                            | Description                                                                                                                                                                   |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `talconfig.yaml`                | Talhelper entrypoint describing cluster topology, schematics, networking, and secrets references.                                                                             |
| `baseconfig/` _(generated)_     | Optional working directory for upstream Talos defaults extracted during new hardware enablement. Created locally when running Talhelper helpers; typically gitignored.        |
| `bootstrap/` _(generated)_      | Local scratch space for bootstrap artifacts (first control-plane secrets, discovery data). Historically populated by install scripts and retained outside Git for security.   |
| `clusterconfig/` _(gitignored)_ | Rendered machine configuration bundle produced by `talhelper genconfig`. Used for `talosctl apply-config` during provisioning and drift remediation.                          |
| `docs/`                         | In-repo operations handbook. Includes [`machine-lifecycle.md`](docs/machine-lifecycle.md) for exhaustive runbook details.                                                     |
| `flux/` _(virtual)_             | Flux applies Talos definitions via the `cluster/machines/` kustomization. Flux bootstrap manifests that seed Talos resources are maintained in `talos/helmfile/` (see below). |
| `helmfile/`                     | Helmfile definitions that pin Flux bootstrap components and Talos support charts (e.g., Cilium).                                                                              |
| `legacy/`                       | Historical installation and upgrade scripts retained for reference. Prefer Taskfile automation and documented procedures instead of invoking these scripts directly.          |
| `patches/`                      | Talos patch library (global, control-plane, etc.) consumed by overlays when generating configs.                                                                               |
| `scripts/` _(virtual)_          | One-off automation is implemented as Taskfile targets (see `.taskfiles/`). Legacy shell scripts remain in `legacy/` for audit purposes.                                       |
| `secrets/` _(virtual)_          | Age-encrypted Talos secrets (`talenv.sops.yaml`, `talsecret.sops.yaml`) live at the repository root. Access requires the platform Age identity.                               |

<!-- markdownlint-enable MD013 -->

> _Generated or virtual directories may be absent in a clean clone. They will
> appear locally when running documented tasks._

## Optional: Prerequisites

- Use the devcontainer or install the required CLIs (`talhelper`, `talosctl`,
  `kubectl`, `flux`, `task`, `age`, `sops`).
- Possess the Age identity that decrypts Talos secrets.
- Maintain the shared hardware inventory (serials, VLANs, rack locations)
  before onboarding nodes.
- Confirm Flux controllers are healthy:

  ```bash
  flux get kustomizations -n flux-system
  ```

## Operation

### Summary

Platform engineering owns the Talos lifecycle. Operators provision
control-plane and worker nodes, drive GitOps workflows for machine
configuration, and coordinate maintenance or recovery actions. Comprehensive
procedures are documented in
[`docs/machine-lifecycle.md`](docs/machine-lifecycle.md) and
[`MAINTENANCE.md`](MAINTENANCE.md); this readme highlights
the key phases.

### Preconditions

- Tooling and secrets access validated as described above.
- Latest `main` branch merged, working from a clean feature branch.
- Out-of-band access (BMC or hypervisor console) available for each node.
- For storage maintenance, ensure Ceph dashboards are accessible and current.

### Procedure

#### Provision new hardware or VMs

1. Update `talconfig.yaml` and overlay snippets under `cluster/machines/` to
   describe the node.
2. Generate configs:

   ```bash
   talhelper genconfig
   ```

   Outputs land in `talos/clusterconfig/`.

3. **Secrets** – Rotate or create Talos secrets when necessary:

   ```bash
   task talos:gen
   ```

4. Boot the host with the appropriate SecureBoot ISO (see
   [Talos image schematics](#talos-image-schematics)).
5. Apply configs once the Talos API responds:

   ```bash
   talosctl apply-config --insecure --nodes <node-ip> \
     --file talos/clusterconfig/<hostname>.yaml
   ```

6. Bootstrap the first control-plane node with `talosctl bootstrap`.

Detailed provisioning guidance lives in
[`docs/machine-lifecycle.md`](docs/machine-lifecycle.md#provisioning-new-hardware-or-vms).

#### GitOps update flow

1. Branch from `main`:

   ```bash
   git checkout -b feat/talos-<change>
   ```

2. Modify overlays and `talos/patches/*` as required.
3. Render diffs without secrets:

   ```bash
   talhelper genconfig --dry-run --diff
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

- **Control plane** – Maintain an odd member count for etcd quorum.
  Taints/labels must remain in place:

  ```bash
  kubectl label node <host> node-role.kubernetes.io/control-plane=
  kubectl taint node <host> node-role.kubernetes.io/control-plane=:NoSchedule
  ```

- **Workers** – Group nodes by hardware class using labels such as
  `node.kubernetes.io/instance-type` or `topology.spruyt-labs.io/rack`. Apply
  workload taints declaratively in overlays.
- **Scaling** – Temporary capacity can be provided by VM overlays; remove the
  overlay and reconcile to decommission.

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
   talosctl --nodes {CP_IP} upgrade-k8s --to v1.34.3 --dry-run
   ```

   - Replace `{CP_IP}` with the control-plane node you are validating.
   - Resolve warnings about deprecated resources or missing manifests before continuing.

3. Execute the upgrade after the dry run succeeds:

   ```bash
   talosctl --nodes {CP_IP} upgrade-k8s --to v1.34.3
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
- Restore etcd snapshots with `talosctl etcd snapshot restore` when quorum is
  lost.
- Rehydrate secrets from SOPS backups and rotate Age identities if compromise is
  suspected.
- Rebuild nodes (wipe, reinstall, reapply) when disks or hardware fail. Sequence
  recovery: control plane → storage workers → remaining pools.

### Validation

- `talosctl health` – global Talos API health.
- `talhelper genconfig --diff` – detect config drift.
- `kubectl get nodes -o wide` and `kubectl describe node <host>` – kubelet
  state, labels, taints.
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

Compare active NIC configuration with the overlay. Use the BMC or hypervisor
console if remediation requires manual intervention.

#### Storage integration issues

```bash
talosctl -n <node-ip> ls /dev/disk/by-id
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

Confirm Ceph OSD placement labels and ensure encrypted volumes unlocked
correctly.

#### Machineconfig drift

```bash
talhelper genconfig --diff
talosctl -n <node-ip> get appliedconfiguration
talosctl apply-config --nodes <node-ip> --file talos/clusterconfig/<hostname>.yaml
```

Rotate secrets with `task talos:gen` if drift stems from credential mismatch.

#### Diagnostic command quick reference

| Target                | Command                             |
| --------------------- | ----------------------------------- |
| Kernel logs           | `talosctl -n <node-ip> dmesg`       |
| Talos services        | `talosctl -n <node-ip> logs`        |
| Kubernetes components | `talosctl -n <node-ip> logs -k`     |
| etcd                  | `talosctl -n <node-ip> logs etcd`   |
| Privileged pod shell  | `task dev-env:priv-pod node=<node>` |

### Escalation

- Post incidents in the platform on-call channel with Talos logs, Flux status,
  recent commit hashes, and remediation attempts.
- Engage hardware owners for physical faults or BMC access issues.
- Coordinate with the storage lead when Ceph flags remain set or OSDs fail to
  recover.
- Escalate to security for Age identity rotation or secrets compromise.

## Talos Image Schematics

<!-- markdownlint-disable MD013 -->

| Hardware class            | Schematic ID                                                       | SecureBoot ISO                                                                                                                                  | Upgrade image                                                                                                           |
| ------------------------- | ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Bossgame E2 control plane | `7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6` | [Download](https://factory.talos.dev/image/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6/v1.11.6/metal-amd64-secureboot.iso) | `factory.talos.dev/metal-installer-secureboot/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6:v1.11.6` |

Your image schematic ID is: `7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6`

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
    - mitigations=off
    - security=none
    - init_on_alloc=0
    - init_on_free=0
    - talos.auditd.disabled=1
    - apparmor=0
  systemExtensions:
    officialExtensions:
      - siderolabs/amd-ucode
      - siderolabs/iscsi-tools
      - siderolabs/lldpd
      - siderolabs/nvme-cli
      - siderolabs/util-linux-tools
```

| MS-01 worker | `7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf` | [Download](https://factory.talos.dev/image/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf/v1.11.6/metal-amd64-secureboot.iso) | `factory.talos.dev/metal-installer-secureboot/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf:v1.11.6` |

Your image schematic ID is: `7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf`

```yaml
customization:
  extraKernelArgs:
    - -lockdown
    - lockdown=integrity
    - quiet
    - loglevel=3
    - intel_iommu=on
    - iommu=pt
    - talos.auditd.disabled=1
    - mitigations=off
    - net.ifnames=0
    - apparmor=0
    - security=none
    - init_on_alloc=0
    - init_on_free=0
  systemExtensions:
    officialExtensions:
      - siderolabs/i915
      - siderolabs/intel-ucode
      - siderolabs/iscsi-tools
      - siderolabs/lldpd
      - siderolabs/thunderbolt
      - siderolabs/util-linux-tools
```

<!-- markdownlint-enable MD013 -->

Additional asset: SecureBoot UKI –
<https://factory.talos.dev/image/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb/v1.11.6/metal-amd64-secureboot-uki.efi>

## References

- Repository runbook standards –
  [`README.md`](../README.md#runbook-standards)
- Machine lifecycle deep dive –
  [`docs/machine-lifecycle.md`](docs/machine-lifecycle.md)
- Flux GitOps workflows –
  [`cluster/flux/README.md`](../cluster/flux/README.md)
- Application runbooks –
  [`cluster/apps/README.md`](../cluster/apps/README.md)
- Talos upstream documentation – <https://www.talos.dev/>
- Talhelper project – <https://github.com/budimanjojo/talhelper>
- FluxCD documentation – <https://fluxcd.io/>
- Ceph maintenance reference – <https://rook.io/docs/rook/latest/>
