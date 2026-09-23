# Cloudflare Terraform Workspace

## Overview

Manages the Cloudflare zone and tunnel that front the cluster. Runs in the `cloudflare` Terraform Cloud workspace, created by [`workspace-factory`](../workspace-factory).

The repo is public, so the account ID, zone name, and domain-identifying DNS tokens are passed in as sensitive TFC variables. Nothing here should contain the real domain.

## What is managed

| File               | Resources                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `tunnel.tf`        | Tunnel `spruyt-labs-01`, its remote ingress config, and one proxied CNAME per route         |
| `dns.tf`           | Static DNS records (Brevo DKIM/verification, SPF, DMARC, site verification, Home Assistant) |
| `rulesets.tf`      | Custom firewall rules, rate limiting, cache rules                                           |
| `zone-settings.tf` | Security and TLS zone settings                                                              |

## What is not managed

- **Email Routing** MX and DKIM records (read-only, owned by Email Routing) and routing rules (contain personal addresses). Manage in the dashboard.
- **cert-manager DNS01 API token** (`solver-secrets`). Creating API tokens needs token-admin permissions this workspace does not have. Create it by hand with `Zone:DNS:Edit` and `Zone:Read`.
- **Tunnel secret**. `tunnel_secret` is ignored; the connector token lives in `cluster/apps/cloudflare-system/cloudflared/app/cloudflared-secrets.sops.yaml`.
- **external-dns** does not touch Cloudflare (it only writes to Technitium), so there is no record ownership conflict.

## Variables

Set on the `workspace-factory` TFC workspace, which copies them to this workspace as write-only values (never stored in the factory state or plan). After changing any of them, bump `cloudflare_tfc_variables_version` in [`variables.auto.tfvars`](../workspace-factory/variables.auto.tfvars) so the next factory apply pushes the new values:

| workspace-factory variable    | This workspace          | Notes                         |
| ----------------------------- | ----------------------- | ----------------------------- |
| `cloudflare_api_token`        | `CLOUDFLARE_API_TOKEN`  | env, sensitive                |
| `cloudflare_account_id`       | `cloudflare_account_id` | sensitive                     |
| `cloudflare_zone_name`        | `zone_name`             | sensitive                     |
| `cloudflare_dns_verification` | `dns_verification`      | sensitive HCL map, keys below |

`dns_verification` keys: `brevo_code`, `google_site`, `microsoft`, `twilio`, `dmarc_cloudflare_rua`, `nabu_casa_remote_ui_id`. Values are the token parts only (no `brevo-code:` / `MS=` prefixes, no `@dmarc-reports.cloudflare.net` suffix).

### API token permissions

- Account: `Cloudflare Tunnel:Edit`
- Zone: `Zone:Read`, `DNS:Edit`, `Zone Settings:Edit`, `Zone WAF:Edit`, `Cache Rules:Edit`

## Adding a tunnel route

Add an entry to `local.tunnel_routes` in `tunnel.tf`. That creates both the ingress rule and the proxied CNAME. Do not add routes in the dashboard; the next apply will remove them.

Order matters: cloudflared matches ingress rules top-down, and the `http_status:404` catch-all is always appended last.

## Initial import

`imports.tf` adopts the existing clickops resources on the first apply. The first plan must show only imports (0 to add, 0 to change, 0 to destroy). Delete `imports.tf` after that apply.
