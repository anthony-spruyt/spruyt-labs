# Talos

## Generating or Rotating Secrets

Run the task `task talos:gen` and select yes when prompted to generate new secrets.

## Talos Linux Image Factory

### E2 Control Plane Schematic

[Talos Image Factory URL](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-lockdown+lockdown%3Dintegrity+quiet+loglevel%3D3+amd_pstate%3D1&cmdline-set=true&extensions=-&extensions=siderolabs%2Famd-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Flldpd&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=true&target=metal&version=1.11.2)

Your image schematic ID is: `a25c479f21f7bad71d7d7425b03fe60db9c83901bd68fe963ca16841e6f4fd16`

```yaml
customization:
  extraKernelArgs:
    - -lockdown # Secure boot lockdown needs updating
    - lockdown=integrity # to integrity for Cilium
    - quiet # Reduce noise
    - loglevel=3 # Reduce noise
    - amd_pstate=1 # Enable AMD CPU boost
    # - talos.auditd.disabled=1 # Less security, faster computer
    # - mitigations=off # Less security, faster computer
    # - apparmor=0 # Less security, faster computer
    # - security=none # Less security, faster computer
    # - init_on_alloc=0 # Less security, faster computer
    # - init_on_free=0 # Less security, faster computer
  systemExtensions:
    officialExtensions:
      - siderolabs/amd-ucode
      - siderolabs/lldpd
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
```

#### First Boot

##### SecureBoot ISO

[https://factory.talos.dev/image/a25c479f21f7bad71d7d7425b03fe60db9c83901bd68fe963ca16841e6f4fd16/v1.11.2/metal-amd64-secureboot.iso](https://factory.talos.dev/image/a25c479f21f7bad71d7d7425b03fe60db9c83901bd68fe963ca16841e6f4fd16/v1.11.2/metal-amd64-secureboot.iso) [(SecureBoot documentation)](https://www.talos.dev/v1.11/talos-guides/install/bare-metal-platforms/secureboot/)

#### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:

> factory.talos.dev/metal-installer-secureboot/a25c479f21f7bad71d7d7425b03fe60db9c83901bd68fe963ca16841e6f4fd16:v1.11.2

#### Upgrading Talos Linux

To [upgrade](https://www.talos.dev/v1.11/talos-guides/upgrading-talos/) Talos Linux on the machine, use the following image:

> factory.talos.dev/metal-installer-secureboot/a25c479f21f7bad71d7d7425b03fe60db9c83901bd68fe963ca16841e6f4fd16:v1.11.2

### MS-01 Worker Schematic

[Talos Image Factory URL](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-lockdown+lockdown%3Dintegrity+quiet+loglevel%3D3+intel_iommu%3Don+iommu%3Dpt&cmdline-set=true&extensions=-&extensions=siderolabs%2Fi915&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Flldpd&extensions=siderolabs%2Fthunderbolt&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=true&target=metal&version=1.11.2)

Your image schematic ID is: `358b87443e77784112467ac042afcf9f96ad38c0d2de23d157d836b1eb44a5e8`

```yaml
customization:
  extraKernelArgs:
    - -lockdown # Secure boot lockdown needs updating
    - lockdown=integrity # to integrity for Cilium
    - quiet # Reduce noise
    - loglevel=3 # Reduce noise
    - intel_iommu=on # PCI Passthrough
    - iommu=pt # PCI Passthrough
    # - talos.auditd.disabled=1 # Less security, faster computer
    # - mitigations=off # Less security, faster computer
    # - apparmor=0 # Less security, faster computer
    # - security=none # Less security, faster computer
    # - init_on_alloc=0 # Less security, faster computer
    # - init_on_free=0 # Less security, faster computer
  systemExtensions:
    officialExtensions:
      - siderolabs/i915
      - siderolabs/intel-ucode
      - siderolabs/lldpd
      - siderolabs/thunderbolt
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
```

#### First Boot

##### SecureBoot ISO

[https://factory.talos.dev/image/358b87443e77784112467ac042afcf9f96ad38c0d2de23d157d836b1eb44a5e8/v1.11.2/metal-amd64-secureboot.iso](https://factory.talos.dev/image/358b87443e77784112467ac042afcf9f96ad38c0d2de23d157d836b1eb44a5e8/v1.11.2/metal-amd64-secureboot.iso) [(SecureBoot documentation)](https://www.talos.dev/v1.11/talos-guides/install/bare-metal-platforms/secureboot/)

#### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:

> factory.talos.dev/metal-installer-secureboot/358b87443e77784112467ac042afcf9f96ad38c0d2de23d157d836b1eb44a5e8:v1.11.2

#### Upgrading Talos Linux

To [upgrade](https://www.talos.dev/v1.11/talos-guides/upgrading-talos/) Talos Linux on the machine, use the following image:

> factory.talos.dev/metal-installer-secureboot/358b87443e77784112467ac042afcf9f96ad38c0d2de23d157d836b1eb44a5e8:v1.11.2

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
