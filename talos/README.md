# Talos

## Generating or Rotating Secrets

Run the task `task talos:gen` and select yes when prompted to generate new secrets.

## Talos Linux Image Factory

### E2 Control Plane Schematic

[Talos Image Factory URL](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-lockdown+lockdown%3Dintegrity+quiet+loglevel%3D3+amd_pstate%3D1+pcie_aspm%3Doff+pci%3Dpcie_bus_perf+nvme_core.default_ps_maxlatency_us%3D0+iommu%3Dpt+idle%3Dnomwait+mitigations%3Doff+security%3Dnone+init_on_alloc%3D0+init_on_free%3D0+talos.auditd.disabled%3D1+apparmor%3D0&cmdline-set=true&extensions=-&extensions=siderolabs%2Famd-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Flldpd&extensions=siderolabs%2Fnvme-cli&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=true&target=metal&version=1.11.2)

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

#### First Boot

##### SecureBoot ISO

[https://factory.talos.dev/image/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6/v1.11.2/metal-amd64-secureboot.iso](https://factory.talos.dev/image/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6/v1.11.2/metal-amd64-secureboot.iso) [(SecureBoot documentation)](https://www.talos.dev/v1.11/talos-guides/install/bare-metal-platforms/secureboot/)

#### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:

> factory.talos.dev/metal-installer-secureboot/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6:v1.11.2

#### Upgrading Talos Linux

To [upgrade](https://www.talos.dev/v1.11/talos-guides/upgrading-talos/) Talos Linux on the machine, use the following image:

> factory.talos.dev/metal-installer-secureboot/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6:v1.11.2

### MS-01 Worker Schematic

[Talos Image Factory URL](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-lockdown+lockdown%3Dintegrity+quiet+loglevel%3D3+intel_iommu%3Don+iommu%3Dpt+talos.auditd.disabled%3D1+mitigations%3Doff+net.ifnames%3D0+apparmor%3D0+security%3Dnone+init_on_alloc%3D0+init_on_free%3D0&cmdline-set=true&extensions=-&extensions=siderolabs%2Fi915&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Flldpd&extensions=siderolabs%2Fthunderbolt&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=true&target=metal&version=1.11.2)

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

#### First Boot

##### SecureBoot ISO

[https://factory.talos.dev/image/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf/v1.11.2/metal-amd64-secureboot.iso](https://factory.talos.dev/image/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf/v1.11.2/metal-amd64-secureboot.iso) [(SecureBoot documentation)](https://www.talos.dev/v1.11/talos-guides/install/bare-metal-platforms/secureboot/)

#### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:

> factory.talos.dev/metal-installer-secureboot/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf:v1.11.2

#### Upgrading Talos Linux

To [upgrade](https://www.talos.dev/v1.11/talos-guides/upgrading-talos/) Talos Linux on the machine, use the following image:

> factory.talos.dev/metal-installer-secureboot/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf:v1.11.2

### Gracefully Shutdown

#### Ceph Quiescence

##### Set Ceph Flags

Exec into the rook ceph tools pod:

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

Prevent Ceph from reacting to node shutdowns:

```bash
ceph osd set noout
ceph osd set nodown
ceph osd set norebalance
ceph osd set nobackfill
ceph osd set norecover
```

##### Scale Down Rook Operator

Prevent it from auto-restarting components:

```bash
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=0
```

##### Scale Down Ceph Components

Order matters—mons last:

```bash
kubectl -n rook-ceph scale deployment rook-ceph-osd-0 --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-osd-1 --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-osd-2 --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-a --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-b --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-c --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mgr-d --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-a --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-b --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-c --replicas=0
kubectl -n rook-ceph scale deployment rook-ceph-mon-d --replicas=0
```

#### Talos Node Shutdown

Use Talos API or CLI to shut down nodes cleanly:

```bash
talosctl shutdown -n <node 3>
talosctl shutdown -n <node 2>
talosctl shutdown -n <node 1>
```

#### Restart Sequence

##### 1 Bring Talos Nodes Back Online

Boot nodes in reverse order if needed to restore etcd quorum.

##### Scale Up Ceph Components

Order matters—mons first:

```bash
kubectl -n rook-ceph scale deployment rook-ceph-mon-a --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-b --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-c --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-d --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mon-e --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-a --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-b --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-c --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-mgr-d --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-0 --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-1 --replicas=1
kubectl -n rook-ceph scale deployment rook-ceph-osd-2 --replicas=1
```

##### Scale Up Rook Operator

```bash
kubectl -n rook-ceph scale deployment rook-ceph-operator --replicas=1
```

##### Unset Ceph Flags

Exec into the rook ceph tools pod:

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

Unset the flags

```bash
ceph osd unset noout
ceph osd unset nodown
ceph osd unset norebalance
ceph osd unset nobackfill
ceph osd unset norecover
```

##### Restart Apps

Bring back Vaultwarden, Mosquitto, Chrony, etc.

### Logs

The logs of a talos node can be viewed by running the following against a node.

#### Kernel

```bash
talosctl -n <NODE_IP> dmesg
```

#### Service

```bash
talosctl logs
```

#### Container

```bash
talosctl logs -k
```

### Extra Assets

#### SecureBoot UKI

[https://factory.talos.dev/image/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb/v1.11.2/metal-amd64-secureboot-uki.efi](https://factory.talos.dev/image/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb/v1.11.2/metal-amd64-secureboot-uki.efi)

## Resources

- [Talos 1.11 Configuration Reference & Documentation](https://www.talos.dev/v1.11/reference/configuration/v1alpha1/config/)
