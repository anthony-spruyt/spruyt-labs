# cert-manager - Certificate Management

## Overview

Issues every TLS certificate in the cluster via ACME DNS01 against Cloudflare, including the Traefik wildcard default certificate and the per-host `*.lan.${EXTERNAL_DOMAIN}` certificates.

## Prerequisites

- **Cloudflare API token** in `app/solver-secrets.sops.yaml` (`CLOUDFLARE_API_TOKEN`) with `Zone:DNS:Edit` and `Zone:Read` on the zone. Created by hand in the Cloudflare dashboard, not by Terraform - the `cloudflare` workspace lacks token-admin permissions (see [`infra/terraform/cloudflare/README.md`](../../../../infra/terraform/cloudflare/README.md)).
- **ZeroSSL EAB credentials**: key ID in `ZEROSSL_EAB_KID` (cluster-secrets), HMAC key in `app/zerossl-eab-secret.sops.yaml`. Both come from the ZeroSSL dashboard.

## Operations

### Choosing the issuer

Three `ClusterIssuer`s exist (`letsencrypt-staging`, `letsencrypt-production`, `zerossl-production`). Nothing references them by name: every `Certificate` and IngressRoute annotation uses `${CLUSTER_ISSUER}` from `cluster/flux/meta/cluster-settings.yaml`. Switch issuers cluster-wide by changing that one value; use `letsencrypt-staging` when iterating to stay clear of production rate limits.

### Why DNS01 self-checks bypass cluster DNS

`dns01RecursiveNameserversOnly` is set because in-cluster DNS forwards `${EXTERNAL_DOMAIN}` to Technitium (see the CoreDNS Corefile in `cluster/apps/kube-system/coredns/`). Technitium holds the internal copy of the zone and never sees the `_acme-challenge` TXT record written to Cloudflare, so the propagation self-check would never pass. Do not remove it.

## References

- [cert-manager DNS01 Cloudflare](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/)
- [ZeroSSL ACME EAB](https://zerossl.com/documentation/acme/)
