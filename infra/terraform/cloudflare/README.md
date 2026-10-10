# Cloudflare Terraform Workspace

## Overview

Manages the Cloudflare zone and tunnel that front the cluster. Runs in the `cloudflare` Terraform Cloud workspace, created by [`workspace-factory`](../workspace-factory).

The repo is public, so the account ID, zone name, and domain-identifying DNS tokens are passed in as sensitive TFC variables. Nothing here should contain the real domain.

## What is managed

| File               | Resources                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------- |
| `tunnel.tf`        | Tunnel `spruyt-labs-01`, its remote ingress config, and one proxied CNAME per route         |
| `access.tf`        | Access application, policy and service token that gate the `litellm` host for CI            |
| `dns.tf`           | Static DNS records (Brevo DKIM/verification, SPF, DMARC, site verification, Home Assistant) |
| `rulesets.tf`      | Custom firewall rules, rate limiting, cache rules                                           |
| `zone-settings.tf` | Security and TLS zone settings                                                              |

Authentik admin paths are limited to the home IPs in `home_ip` by a Cloudflare WAF rule (`rulesets.tf`).

## LiteLLM external access for CI

GitHub-hosted runners reach the `litellm` host through the tunnel. On the LAN the same hostname resolves straight to Traefik, so none of this applies there.

- `rulesets.tf`: from the internet only `/v1/messages`, `/v1/messages/count_tokens`, `/v1/chat/completions` and `/health/liveliness` pass (lower-cased, URL-decoded exact match). The country condition of "Block non-AU traffic and bots" skips this host; the bot condition still applies.
- `access.tf`: a self-hosted Access application on the host whose only policy allows the `litellm-ci` service token (`non_identity` decision). The token never expires; rotate it by bumping `client_secret_version` and setting `previous_client_secret_expires_at` on the token (the provider requires both).
- `tunnel.tf`: the `litellm` ingress rule and CNAME `depends_on` the Access application and the firewall ruleset, so a failed create of either leaves the host unrouted. This also orders every other route change after them.
- The `litellm_ci_access_client_id` and `litellm_ci_access_client_secret` (sensitive) outputs hold the `CF-Access-Client-Id` / `CF-Access-Client-Secret` values. Read them from the workspace outputs and store them as CI secrets; see the [LiteLLM README](../../../cluster/apps/litellm/README.md#external-access-for-ci).

The "Allow GitHub Webhooks" rule skips the `auth` and `litellm` hosts, so their rules always apply, and lists GitHub's published `hooks` ranges (`gh api meta`). Refresh it when that list changes.

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
| `cloudflare_home_ip`          | `home_ip`               | sensitive                     |
| `cloudflare_dns_verification` | `dns_verification`      | sensitive HCL map, keys below |

When the home IP changes, update `cloudflare_home_ip` on workspace-factory, bump `cloudflare_tfc_variables_version`, then run the workspace-factory apply followed by the `cloudflare` apply.

`dns_verification` keys: `brevo_code`, `google_site`, `microsoft`, `twilio`, `dmarc_cloudflare_rua`, `nabu_casa_remote_ui_id`. Values are the token parts only (no `brevo-code:` / `MS=` prefixes, no `@dmarc-reports.cloudflare.net` suffix).

### API token permissions

- Account: `Cloudflare Tunnel:Edit`, `Access: Apps and Policies:Edit`, `Access: Service Tokens:Edit`
- Zone: `Zone:Read`, `DNS:Edit`, `Zone Settings:Edit`, `Zone WAF:Edit`, `Cache Rules:Edit`

## Adding a tunnel route

Add an entry to `local.tunnel_routes` in `tunnel.tf`. That creates both the ingress rule and the proxied CNAME. Do not add routes in the dashboard; the next apply will remove them.

Order matters: cloudflared matches ingress rules top-down, and the `http_status:404` catch-all is always appended last.
