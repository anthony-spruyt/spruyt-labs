# CoreDNS - Cluster DNS

## Overview

Flux runs all of CoreDNS from the upstream `coredns` Helm chart: Deployment, Service, ConfigMap, ServiceAccount and RBAC. The Corefile adds a split-DNS zone that sends `${EXTERNAL_DOMAIN}` and all its subdomains to the two Technitium servers, so in-cluster workloads resolve LAN-only hostnames (`*.lan.${EXTERNAL_DOMAIN}`) and internal records the public zone does not have.

## Prerequisites

- **Talos renders no CoreDNS** (`talos/patches/control-plane/19-disable-coredns.yaml`). `talosctl upgrade-k8s` re-applies every manifest Talos renders, so while Talos owned CoreDNS each Kubernetes upgrade rewrote the Corefile and dropped the split-DNS zone. Do not use `cluster.coreDNS.disabled`; `KubeCoreDNSConfig` is the switch.
- **Bootstrap**: `talos/helmfile/coredns.yaml.gotmpl` installs the chart before Flux on a rebuild, with `talos/helmfile/coredns-values.yaml` swapping in a Corefile without the split-DNS zone (Technitium is not running yet). Flux then upgrades the same release to the full values. See [bootstrap.md](../../../../docs/bootstrap.md#3b-coredns).

## Operations

- **Names and addresses are pinned to the live objects.** `fullnameOverride`, `k8sAppLabelOverride`, `deployment.selector`, `service.name`, `service.selector` and `clusterRole.nameOverride` in `app/values.yaml` keep the Talos-era Deployment selector and the `system:coredns` RBAC names.
  `talos/helmfile/coredns-values.yaml` pins the Service IP the kubelets hand out as `clusterDNS` for the bootstrap install only; Flux never sets it, so the live IP stays. Neither the selector nor the Service IP can change in place.
- **Edit the Corefile in `servers` in `app/values.yaml`.** The Deployment rolls on the config checksum. Keep the `.:53` block of `talos/helmfile/coredns-values.yaml` in step with it, because Helm replaces lists whole and the bootstrap install ignores everything else in `servers`.
- **Helm never deletes the DNS objects.** `customAnnotations` puts `helm.sh/resource-policy: keep` on all of them, so an uninstall, a rename or a failed install leaves DNS running.
- **Chart and image bumps are high risk.** A Renovate PR for the chart (`cluster/flux/meta/repositories/oci/coredns-ocirepo.yaml`) or for `image.tag` changes cluster DNS: triage it as high risk.
- **Break-glass rollback** needs no in-cluster DNS, so run it from the devcontainer:

  ```bash
  flux suspend hr coredns -n kube-system
  helm -n kube-system history coredns
  helm -n kube-system rollback coredns <revision>
  ```

  Fix the cause in Git, then `flux resume hr coredns -n kube-system`.

- **VPA**: `app/vpa.yaml` (`Initial`) sets pod requests at creation, so running pods differ from the Deployment spec. `maxAllowed` mirrors the memory limit in `app/values.yaml`; change both together.
- **Side effect worth knowing**: anything in the cluster that resolves `${EXTERNAL_DOMAIN}` gets Technitium's answer, not Cloudflare's. cert-manager is configured to ignore cluster DNS for DNS01 checks for this reason.

## References

- [CoreDNS chart](https://github.com/coredns/helm/tree/master/charts/coredns)
