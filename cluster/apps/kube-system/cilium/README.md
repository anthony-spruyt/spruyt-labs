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
- **Hubble certificates renew via the chart's certgen CronJob** (`hubble.tls.auto.method: cronJob`): the default `helm` method reuses the existing Secrets on every upgrade, so the 365-day certificates expired and broke `hubble-relay` (#3543). The CronJob reissues the Hubble leaf certificates on the first of every fourth month (chart default schedule); agents and relay reload them from disk without
  a restart. It reuses the `cilium-ca` CA, which lasts 3 years: about 2 years in, runs fail (`KubeJobFailed`) because a new leaf would outlive the CA. Delete the `cilium-ca` Secret and re-run the CronJob to issue a new CA and leaves.
- **Envoy closes each upstream connection after one request** (`envoy.maxRequestsPerConnection: 1`): for traffic under an L7 policy, Envoy on the source node opens the upstream connection from the pod's address and by default keeps it idle for 60 s. A short-lived pod (agent runs) ends first, so the connection's closing packets reach the destination as `world` and fire `CiliumPolicyDrops` with an
  empty source (#3542). Gateway API listeners would get the same setting. Envoy runs as the separate `cilium-envoy` DaemonSet and reads this from its bootstrap config only at start, so `envoy.rollOutPods: true` restarts it when that config changes.

## References

- [Cilium on Talos](https://www.talos.dev/v1.11/kubernetes-guides/network/deploying-cilium/)
- [Cilium BGP control plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane/)
