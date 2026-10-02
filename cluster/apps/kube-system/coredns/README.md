# CoreDNS - Corefile Override

## Overview

Flux owns only the CoreDNS `ConfigMap` and its `VerticalPodAutoscaler`; the Deployment, Service and image still come from Talos. The override adds a split-DNS stanza that sends `${EXTERNAL_DOMAIN}` and all its subdomains to the two Technitium servers, so in-cluster workloads resolve LAN-only hostnames (`*.lan.${EXTERNAL_DOMAIN}`) and internal records the public zone does not have.

## Operations

- **Talos does not fight this.** Talos applies its bootstrap manifests create-only, so once this ConfigMap exists Talos never rewrites it. The flip side: a new Talos default Corefile will not reach the cluster either; diff against upstream after Talos upgrades if something looks missing.
- **Taking over the Deployment** (for image pinning via Renovate) would need `cluster.coreDNS.disabled` in the Talos machine config first. Not done.
- **VPA on a Talos-owned Deployment**: `app/vpa.yaml` (`Initial`) sets CoreDNS pod requests at creation, so running pods differ from the Deployment spec. `maxAllowed` mirrors the memory limit Talos sets; if a Talos upgrade changes that limit, update `maxAllowed` to match.
- **Side effect worth knowing**: anything in the cluster that resolves `${EXTERNAL_DOMAIN}` gets Technitium's answer, not Cloudflare's. cert-manager is configured to ignore cluster DNS for DNS01 checks for this reason.
