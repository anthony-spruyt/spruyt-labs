# Technitium - Internal DNS

## Overview

Primary internal DNS server (LAN resolver and authoritative for the internal copy of `${EXTERNAL_DOMAIN}` and `lan.${EXTERNAL_DOMAIN}`). `technitium-secondary` replicates from it. external-dns writes records here, and CoreDNS forwards the domain here for in-cluster lookups.

## Prerequisites

- Authentik OIDC provider from `authentik-system/authentik/app/blueprints/technitium-sso.yaml`. One provider serves both instances, with a redirect URI for each.
- TSIG key for external-dns, configured in the Technitium UI (see [external-dns-technitium](../../external-dns/external-dns-technitium/README.md)).

## Operations

### Config lives on the PVC, not in env vars

Technitium reads its `DNS_SERVER_*` environment variables **only on first start** with an empty config directory. After that everything - zones, SSO settings, admin password - is persisted on the PVC and the env vars are ignored. Consequences:

- Changing SSO or the admin password in `app/values.yaml` does nothing on a running instance. Change it in the admin UI (Settings -> SSO) on **each** instance.
- The env vars only matter for a fresh PVC, where SSO auto-configures from them.

### OIDC secret rotation is manual

Technitium is deliberately left out of the weekly Authentik `oauth-secret-rotation` CronJob. That job updates Authentik and the Kubernetes secret, Reloader restarts the pod, and Technitium keeps using the old secret from its PVC - so SSO breaks. To rotate:

1. Generate a new client secret.
2. Update the provider in Authentik (API or admin UI).
3. Update `TECHNITIUM_OIDC_CLIENT_SECRET` in `authentik-technitium-oauth` (`authentik-system`) with `sops`.
4. Enter the new secret in the SSO settings of **both** instances' admin UIs.
5. Test SSO login on both.

### Primary and secondary

Zones reach the secondary by zone transfer (catalog zone, AXFR/IXFR incl. XFR-over-TLS on 853) with NOTIFY from the primary; `app/network-policies.yaml` carries both directions. A required pod anti-affinity on the `role` label keeps primary and secondary on different nodes.

`app/allowlist.txt` (Adblock `@@||domain^` syntax) is not referenced by any manifest - it is not in `kustomization.yaml` and nothing mounts it. It only takes effect if Technitium's blocking settings point at the file's raw GitHub URL; editing it does nothing otherwise.

## Troubleshooting

1. **SSO button missing** - SSO was never enabled in the UI on that instance; env vars alone do not enable it on an existing PVC.
2. **SSO fails with invalid client** - the secret was rotated in Authentik but not re-entered in the Technitium UI.
3. **SSO redirect error** - the redirect URI must match exactly, including port `53443`.
4. **Pod exits 139 with `System.OutOfMemoryException` in the logs (not OOMKilled)** - .NET caps the GC heap at 75% of the container memory limit, so large block lists (e.g. hagezi NRD, millions of domains) exhaust the heap during a reload, when the old and new lists are both in memory, before the kernel OOM killer acts. Raise `limits.memory` in both instances' `app/values.yaml` and `maxAllowed` in
   both `app/vpa.yaml` together.

## References

- [Technitium DNS Server](https://technitium.com/dns/)
