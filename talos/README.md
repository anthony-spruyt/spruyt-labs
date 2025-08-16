# Talos

## Generating or Rotating Secrets

Run the script `talos/generate.sh` and select yes when prompted to generate new secrets.

If secrets are regenerated then `cluster/apps/traefik/traefik/crds/talos-api-tls-secret.sops.yaml` needs to be updated with the new tls values from `talos/clusterconfig/talosconfig`

## Talos Linux Image Factory

[Talos Image Factory URL](https://factory.talos.dev/?arch=amd64&board=undefined&cmdline=-lockdown+lockdown%3Dintegrity&cmdline-set=true&extensions=-&extensions=siderolabs%2Famd-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Futil-linux-tools&platform=metal&secureboot=true&target=metal&version=1.10.5)

Your image schematic ID is: `777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774`

```yaml
customization:
  extraKernelArgs:
    - -lockdown
    - lockdown=integrity
  systemExtensions:
    officialExtensions:
      - siderolabs/amd-ucode
      - siderolabs/iscsi-tools
      - siderolabs/util-linux-tools
```

### First Boot

Here are the options for the initial boot of Talos Linux on a bare-metal machine or a generic virtual machine:

#### SecureBoot ISO

[https://factory.talos.dev/image/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774/v1.10.6/metal-amd64-secureboot.iso](https://factory.talos.dev/image/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774/v1.10.6/metal-amd64-secureboot.iso)
[(SecureBoot documentation)](https://www.talos.dev/v1.10/talos-guides/install/bare-metal-platforms/secureboot/)

### Initial Installation

For the initial installation of Talos Linux (not applicable for disk image boot), add the following installer image to the machine configuration:
`factory.talos.dev/metal-installer-secureboot/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774:v1.10.6`

### Upgrading Talos Linux

To [upgrade](https://www.talos.dev/v1.10/talos-guides/upgrading-talos/) Talos Linux on the machine, use the following image:
`factory.talos.dev/metal-installer-secureboot/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774:v1.10.6`

### Extra Assets

#### SecureBoot UKI

[https://factory.talos.dev/image/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774/v1.10.6/metal-amd64-secureboot-uki.efi](https://factory.talos.dev/image/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774/v1.10.6/metal-amd64-secureboot-uki.efi)

## Resources

- [Talos 1.10 Configuration Reference & Documentation](https://www.talos.dev/v1.10/reference/configuration/)
