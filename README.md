# spruyt-labs

This is a WIP setting up a home lab. The aim is to build a cluster on the talos ecosystem with internal ??? ingress, cilium and cloud flare tunneling with SNI-based routing and path based rules to multiplex traffic for external ingress with a focus on security and encryption for local and external traffic.

Project progress:

- [x] Talos secrets
- [x] Talos generate
- [x] Talos apply
- [x] Talos bootstrap
- [x] Cilium install via helm
- [x] Bootstrap flux
- [x] Flux takes over Cilium management
- [ ] Ingress
- [ ] Cert management
- [ ] Cloudflare tunnel

## Talos

OS of choice for Bossgame e2 controller planes and Raspberry Pi 4 workers

[https://www.talos.dev/](https://www.talos.dev/)

## FluxCD

gitops via FluxCD

[https://fluxcd.io/](https://fluxcd.io/)

## Cilium

CNI to secure sensitive services such as Vaultwarden.

Helm Reference: [text](https://docs.cilium.io/en/stable/helm-reference/)

[https://github.com/cilium/cilium](https://github.com/cilium/cilium)

## Cloudflare

Cloudflare tunneling to avoid having to forward any ports.

[https://github.com/adyanth/cloudflare-operator](https://github.com/adyanth/cloudflare-operator)

## Traefik

Use traefik for local ingress

[https://doc.traefik.io/](https://doc.traefik.io/)

Other possible options if traefik is a pain are:
- [https://github.com/caddyserver/ingress](https://github.com/caddyserver/ingress)
- [https://github.com/kubernetes/ingress-nginx](https://github.com/kubernetes/ingress-nginx)

## Cert Manager

Do I need cert manager if using some of the above?

Cert manager with local self signed certs and cloudflare + lets encrypt ACME for spruyt.xyz and subdomains.

[https://cert-manager.io/](https://cert-manager.io/)

## Guard Rails

Mark dangerous or sensitive resources with label:

```
metadata:
  annotations:
    spruyt-labs/guardrail: "true"
```

# Project folder structure

.
├── cluster
│   ├── flux-system
│   │   ├── gotk-components.yaml
│   │   ├── gotk-sync.yaml
│   │   └── kustomization.yaml
│   ├── infrastructure
│   │   ├── configs
│   │   └── controllers
│   │       ├── cilium
│   │       │   ├── cilium-values.yaml
│   │       │   └── cilium.yaml
│   │       │   └── network-policies
│   │       │       └── allow-all.yaml
│   │       ├── kustomization.yaml
│   │       └── traefik
│   │           └── traefik.yaml
│   └── infrastructure.yaml
├── flux
│   └── rendered.yaml
├── scripts
│   ├── apply.sh
│   ├── bootstrap.sh
│   ├── check-guardrails.sh
│   ├── cilium-install-via-cli.sh
│   ├── cilium-install-via-helm.sh
│   ├── config.example.sh
│   ├── config.sh
│   ├── debug-dump.sh
│   ├── flux-bootstrap.sh
│   ├── flux-install.sh
│   ├── flux-test.sh
│   ├── generate.sh
│   ├── guardrail.yaml
│   ├── helm-install.sh
│   ├── install.sh
│   ├── paths.sh
│   ├── reset-node.sh
│   ├── secrets.sh
│   └── sync.sh
├── secrets
├── talos
│   ├── config
│   │   ├── cilium.yaml
│   │   ├── controlplane.ctrl-e2-1.yaml
│   │   └── worker.wrk-pi4b4gb-1.yaml
│   └── patches
│       ├── allow-scheduling-on-control-planes.yaml
│       ├── disable-flannel.yaml
│       ├── disable-kubeproxy.yaml
│       └── wipe-disk.yaml