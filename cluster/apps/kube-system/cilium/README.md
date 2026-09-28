# Cilium - CNI, Network Policy and BGP

## Overview

CNI and kube-proxy replacement, native routing, BGP advertisement of LoadBalancer IPs to the gateway, Gateway API and Hubble. Installed once at bootstrap by helmfile, then owned by Flux.

## Prerequisites

Outside `ks.yaml`:

- **Talos**: Flannel removed (`talos/patches/control-plane/17-disable-flannel-cni.yaml`), kube-proxy disabled (`18-disable-kube-proxy-for-cilium.yaml.tpl`), KubePrism on 7445 (`all/10-enable-kube-prism.yaml`) which is what `k8sServiceHost: localhost` / `k8sServicePort: 7445` point at.
- **Talos host DNS**: `forwardKubeDNSToHost: false` in `talos/patches/all/11-host-dns-for-cilium.yaml`. Forwarding kube-dns to the host resolver breaks with BPF masquerade ([siderolabs/talos#8836](https://github.com/siderolabs/talos/issues/8836)).
- **Gateway BGP**: the gateway must peer as ASN 65000 with the cluster's ASN 65050 (`app/bgp-cluster.yaml`). That side is configured in the UniFi UI, not in Git.
- **CRDs**: Gateway API CRDs are seeded by Talos (`07-extra-manifests.yaml`) and then owned by the `gateway-api-crds` Kustomization in `ks.yaml`.

## Operations

### Bootstrap vs Flux values

`talos/helmfile/cilium.yaml.gotmpl` + `cilium-values.yaml` install Cilium on a fresh cluster before Flux exists. The helmfile reads the chart version from `app/release.yaml` and the repo URL from the `cilium-charts` HelmRepository, so there is no separate bootstrap pin to bump. The values are a minimal bootstrap set (policy enforcement off, no BGP or Hubble) and deliberately differ from
`app/values.yaml`; Flux converges to the full config once it runs. Both sets reach the API server through KubePrism, which works on a fresh or an existing cluster.

### Non-default choices

- **No agent memory limit, `system-node-critical`**: an OOM-killed agent took down all networking on a node and cascaded into Ceph (#1035). The CNI must never be cgroup-OOMed.
- **Timeouts**: a full agent rollout takes about 5m. The HelmRelease sets `timeout: 10m` explicitly because Kyverno's HelmRelease defaults do not apply in `kube-system`; the Kustomization timeout must stay above it (#3071).
- **Hubble drop export**: the `policy-drops` dynamic exporter writes every dropped flow to stdout so VictoriaLogs holds full flow context for CNP debugging. The `cnp-drop-investigator` agent and the `task cilium:*` targets rely on it.

## References

- [Cilium on Talos](https://www.talos.dev/v1.11/kubernetes-guides/network/deploying-cilium/)
- [Cilium BGP control plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane/)
