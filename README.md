# spruyt-labs

This is a WIP setting up a home lab.

References:

- [https://github.com/mrwulf/home-cluster](https://github.com/mrwulf/home-cluster)
- [https://github.com/timtorChen/homelab](https://github.com/timtorChen/homelab)
- [https://github.com/d4rkfella/home-ops](https://github.com/d4rkfella/home-ops)
- [https://github.com/xunholy/k8s-gitops](https://github.com/xunholy/k8s-gitops) for minecraft hosting on k8s

## Talos

OS of choice for Bossgame e2 controller planes and Raspberry Pi 4 workers

[https://www.talos.dev/](https://www.talos.dev/)

[https://github.com/budimanjojo/talhelper](https://github.com/budimanjojo/talhelper)

TODO: investigate [https://github.com/trueforge-org/truecharts/releases](https://github.com/trueforge-org/truecharts/releases)

## FluxCD

gitops via FluxCD

[https://fluxcd.io/](https://fluxcd.io/)

## Cilium

CNI and much more to secure sensitive services such as Vaultwarden.

Helm Reference: [text](https://docs.cilium.io/en/stable/helm-reference/)

[https://github.com/cilium/cilium](https://github.com/cilium/cilium)

## Metallb

[https://metallb.io/](https://metallb.io/)

## Traefik

Use traefik for local ingress

[https://doc.traefik.io/](https://doc.traefik.io/)

## Rook Ceph

Rook is a storage orchestrator for k8s. Use this on disks that can be fully owned by ceph

[https://github.com/rook/rook](https://github.com/rook/rook)

[How to handle encryption](https://rook.io/docs/rook/latest/Storage-Configuration/Ceph-CSI/ceph-csi-drivers/#enable-rbd-and-cephfs-encryption-support)

How to debug via rook-ceph-tools: `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash`

How to archive health warnings:

```bash
kubectl -n rook-ceph exec -it rook-ceph-<pod> -- bash
ceph crash ls
ceph crash archive-all
```

To get the newly generated UI password after bootstrapping a new cluster run the following:
`kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo`

## Velero

Backup and DR for Rook Ceph

- [https://velero.io/](https://velero.io/)
- [https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/README.md](https://github.com/vmware-tanzu/helm-charts/blob/main/charts/velero/README.md)
- [https://github.com/vmware-tanzu/velero-plugin-for-aws](https://github.com/vmware-tanzu/velero-plugin-for-aws)

## Cloudflared

Cloudflare tunneling to avoid having to forward any ports.

[https://github.com/cloudflare/cloudflared](https://github.com/cloudflare/cloudflared)

## Cert Manager

Cert manager with local self signed certs and Cloudflare + lets encrypt ACME for mydomain.com and subdomains.

[https://cert-manager.io/](https://cert-manager.io/)

## Victoria Metrics & Logs

- [https://docs.victoriametrics.com/](https://docs.victoriametrics.com/)
- [https://vector.dev/docs/](https://vector.dev/docs/)

## Minecraft

TODO: document
bedrock connect, DNS interception and minecraft bedrock server

## UniFi

[https://github.com/jacobalberty/unifi-docker](https://github.com/jacobalberty/unifi-docker)

## Helm Values

Use the following regular expression on GitHub to find YAML language server schemas: `/yaml-language-server:\s*[^\n]*appkeyword[^\n]*\.json/`

## Kilocode

### MCP Servers

#### Context7

- [https://github.com/upstash/context7](https://github.com/upstash/context7)
- [https://context7.com/dashboard](https://context7.com/dashboard)

## Debug containerd crashes

- `talosctl -n {NODE_IP} logs containerd`
- `talosctl -n {NODE_IP} logs cri`
