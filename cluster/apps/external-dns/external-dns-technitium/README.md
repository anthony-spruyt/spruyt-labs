# external-dns-technitium - Internal DNS Records

## Overview

Writes A records for cluster hostnames into Technitium over RFC2136 (TSIG-authenticated dynamic updates). It never touches Cloudflare; public DNS is Terraform-managed in `infra/terraform/cloudflare/`.

## Prerequisites

- A TSIG key configured in Technitium and allowed to update both zones. The key name and secret are copied by hand into `app/external-dns-technitium-secrets.sops.yaml`.

## Operations

The IngressRoute annotations it needs, the dead `alpha` prefix, and how to opt a route out are in [`.claude/rules/ingress-and-certificates.md`](../../../../.claude/rules/ingress-and-certificates.md#dns-annotations). The one opted-out route today is `auth` in `traefik/ingress/authentik-system/`: it must resolve through Cloudflare, and an internal record breaks SSO.

What stays manual in the Technitium UI:

- HTTPS (SVCB) records - outside the managed record types.
- Records created before external-dns worked (#2999) have no TXT ownership entry, so deleting their workload does not remove them.

## Troubleshooting

1. **Record never appears, logs say "All records are already up to date"**
   - **Cause**: The source found zero endpoints - wrong annotation prefix or missing `target` annotation.
   - **Fix**: Check `external_dns_source_endpoints_total`; if it is 0, fix the annotations.

## References

- [external-dns RFC2136 provider](https://kubernetes-sigs.github.io/external-dns/latest/docs/tutorials/rfc2136/)
