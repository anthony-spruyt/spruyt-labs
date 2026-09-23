# Cloudflared - Cloudflare Tunnel

## Overview

Cloudflared provides secure tunneling to Cloudflare's global network, enabling private network access to internal services without exposing them to the public internet. It serves as the secure access solution for the cluster, providing encrypted tunnels for administrative interfaces and internal services.

## Prerequisites

- Cloudflare account and credentials
- Tunnel, routes, and DNS records managed in [`infra/terraform/cloudflare/`](../../../../infra/terraform/cloudflare/README.md)

## Operation

Tunnel ingress routes and their DNS records live in Terraform. Do not edit them in the Cloudflare dashboard; the next Terraform apply will revert the change. To add a hostname, add an entry to `local.tunnel_routes` in `infra/terraform/cloudflare/tunnel.tf`.

## Troubleshooting

1. **Tunnel authentication failures**

   - **Symptom**: Tunnel not connecting to Cloudflare
   - **Resolution**: Verify Cloudflare credentials and tunnel configuration

2. **Tunnel routes not updating**

   - **Symptom**: Configuration changes not reflected
   - **Resolution**: Check the latest `cloudflare` Terraform Cloud run applied, then restart cloudflared

## References

- [Cloudflared Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
