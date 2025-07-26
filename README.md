# spruyt-labs

This is a WIP setting up a home lab.

References:
- [https://github.com/mrwulf/home-cluster](https://github.com/mrwulf/home-cluster)
- [https://github.com/timtorChen/homelab](https://github.com/timtorChen/homelab)
- [https://github.com/d4rkfella/home-ops](https://github.com/d4rkfella/home-ops)

## Talos

OS of choice for Bossgame e2 controller planes and Raspberry Pi 4 workers

[https://www.talos.dev/](https://www.talos.dev/)

[https://github.com/budimanjojo/talhelper](https://github.com/budimanjojo/talhelper)

## FluxCD

gitops via FluxCD

[https://fluxcd.io/](https://fluxcd.io/)

## Cilium

CNI and much more to secure sensitive services such as Vaultwarden.

Helm Reference: [text](https://docs.cilium.io/en/stable/helm-reference/)

[https://github.com/cilium/cilium](https://github.com/cilium/cilium)

## Traefik

Use traefik for local ingress

[https://doc.traefik.io/](https://doc.traefik.io/)

## Rook Ceph

Rook is a storage orchestrator for k8s. Use this on disks that can be fully owned by ceph

[https://github.com/rook/rook](https://github.com/rook/rook)

[How to handle encryption](https://rook.io/docs/rook/latest/Storage-Configuration/Ceph-CSI/ceph-csi-drivers/#enable-rbd-and-cephfs-encryption-support)

How to debug via rook-ceph-tools: `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash`

To get the newly generated UI password after bootstrapping a new cluster run the following: `kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo`

## Cloudflare

Cloudflare tunneling to avoid having to forward any ports.

[https://github.com/adyanth/cloudflare-operator](https://github.com/adyanth/cloudflare-operator)

## Cert Manager

Cert manager with local self signed certs and cloudflare + lets encrypt ACME for mydomain.com and subdomains.

[https://cert-manager.io/](https://cert-manager.io/)

## Prometheus Stack

Installs core components of the [kube-prometheus stack](https://github.com/prometheus-operator/kube-prometheus), a collection of Kubernetes manifests, [Grafana](http://grafana.com/) dashboards, and [Prometheus rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/) combined with documentation and scripts to provide easy to operate end-to-end Kubernetes cluster monitoring with [Prometheus](https://prometheus.io/) using the [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator).

See the kube-prometheus readme for details about components, dashboards, and alerts.

[https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

## Helm Values

Use the following regex on GitHub to find yaml language server schemas: `/yaml-language-server:\s*[^\n]*appkeyword[^\n]*\.json/`
