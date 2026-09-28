# Cloudflared - Cloudflare Tunnel Connector

## Overview

Runs the connectors for the `spruyt-labs-01` tunnel, the only public ingress path into the cluster. Public hostnames reach Traefik through it; the Flux GitHub webhook bypasses Traefik and goes straight to the notification-controller.

## Prerequisites

- Tunnel, ingress routes and their proxied CNAMEs are managed in [`infra/terraform/cloudflare/`](../../../../infra/terraform/cloudflare/README.md). The tunnel is remote-managed (`config_src = "cloudflare"`), so the pods run with only a token and no local ingress config.
- Connector token (`spruyt-labs-01-token`) lives in `app/cloudflared-secrets.sops.yaml`. Terraform ignores `tunnel_secret`, so rotating it is a manual dashboard step followed by a SOPS update here.

## Operations

To add a public hostname, add an entry to `local.tunnel_routes` in `infra/terraform/cloudflare/tunnel.tf`. Do not edit routes in the Cloudflare dashboard; the next Terraform apply reverts them.

A new route whose backend is not Traefik also needs an egress rule for cloudflared in `cluster/apps/cloudflare-system/network-policies.yaml` (the Flux webhook route is the existing example).

## Troubleshooting

1. **New hostname returns 404 from Cloudflare**
   - **Cause**: The `cloudflare` Terraform Cloud run has not applied, or the route sits below a broader match - ingress rules are matched top-down.
   - **Fix**: Check the latest run applied, and route order in `tunnel.tf`.

## References

- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
