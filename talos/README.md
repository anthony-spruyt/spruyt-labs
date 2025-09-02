# Talos

## Generating or Rotating Secrets

Run the script `talos/generate.sh` and select yes when prompted to generate new secrets.

If secrets are regenerated then `cluster/apps/traefik/traefik/crds/talos-api-tls-secret.sops.yaml` needs to be updated with the new tls values from `talos/clusterconfig/talosconfig`

## Talos Linux Image Factory

[Talos Image Factory URL](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-lockdown+lockdown%3Dintegrity&cmdline-set=true&extensions=-&extensions=siderolabs%2Famd-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=true&target=metal&version=1.10.5)

Your image schematic ID is: `9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61`

```yaml
customization:
  extraKernelArgs:
    - -lockdown
    - lockdown=integrity
    - net.ipv6.conf.default.autoconf=0
    - net.ipv6.conf.default.accept_ra=0
  systemExtensions:
    officialExtensions:
      - siderolabs/amd-ucode
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
```

### First Boot

Here are the options for the initial boot of Talos Linux on a bare-metal machine or a generic virtual machine:

#### SecureBoot ISO

[https://factory.talos.dev/image/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61/v1.10.7/metal-amd64-secureboot.iso](https://factory.talos.dev/image/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61/v1.10.7/metal-amd64-secureboot.iso)
[(SecureBoot documentation)](https://www.talos.dev/v1.10/talos-guides/install/bare-metal-platforms/secureboot/)

### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:
`factory.talos.dev/metal-installer-secureboot/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61:v1.10.7`

### Upgrading Talos Linux

To [upgrade](https://www.talos.dev/v1.10/talos-guides/upgrading-talos/) Talos Linux on the machine, use the following image:
`factory.talos.dev/metal-installer-secureboot/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61:v1.10.7`

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
talosctl shutdown -n 192.168.50.84
talosctl shutdown -n 192.168.50.92
talosctl shutdown -n 192.168.50.99
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

[https://factory.talos.dev/image/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61/v1.10.7/metal-amd64-secureboot-uki.efi](https://factory.talos.dev/image/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61/v1.10.7/metal-amd64-secureboot-uki.efi)

## Resources

- [Talos 1.10 Configuration Reference & Documentation](https://www.talos.dev/v1.10/reference/configuration/v1alpha1/config/)
