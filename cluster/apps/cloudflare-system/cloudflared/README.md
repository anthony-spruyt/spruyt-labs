# Cloudflared - Cloudflare Tunnel

## Overview

Cloudflared provides secure tunneling to Cloudflare's global network, enabling private network access to internal services without exposing them to the public internet. It serves as the secure access solution for the cluster, providing encrypted tunnels for administrative interfaces and internal services.

## Prerequisites

- Cloudflare account and credentials
- DNS records configured in Cloudflare

## Troubleshooting

1. **Tunnel authentication failures**

   - **Symptom**: Tunnel not connecting to Cloudflare
   - **Resolution**: Verify Cloudflare credentials and tunnel configuration

2. **Tunnel routes not updating**

   - **Symptom**: Configuration changes not reflected
   - **Resolution**: Verify tunnel configuration and restart cloudflared

## References

- [Cloudflared Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Cloudflare Zero Trust](https://developers.cloudflare.com/cloudflare-one/)
