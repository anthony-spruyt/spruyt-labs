# Foundry VTT

## Overview

Self-hosted virtual tabletop for the household's tabletop RPG games, exposed publicly so remote players can join. Uses the `felddy/foundryvtt` image, which downloads and installs Foundry itself at startup using the licence credentials.

## Prerequisites

- A foundryvtt.com account with a licence. Its credentials (`FOUNDRY_USERNAME`/`FOUNDRY_PASSWORD`, optionally `FOUNDRY_LICENSE_KEY` and `FOUNDRY_ADMIN_KEY`) go in `app/foundryvtt-secrets.sops.yaml`; the image uses them to download and activate Foundry at startup.
- Public exposure is a Cloudflare Tunnel route (`foundry` in `infra/terraform/cloudflare/tunnel.tf`), not just the IngressRoute. Removing or renaming the host needs both changed.

## Operations

- `FOUNDRY_PROXY_SSL=true` and `FOUNDRY_PROXY_PORT=443` tell Foundry it sits behind a TLS-terminating proxy. Without them, invitation links and A/V point at the container port without TLS.
- Downloaded Foundry releases are cached on the PVC (`CONTAINER_CACHE`), so a restart on the same version does not re-download.
- `CONTAINER_PRESERVE_CONFIG=false` means `options.json` and `admin.txt` are regenerated from env vars on every start. Change server settings in `values.yaml`, not in Foundry's setup UI. If `FOUNDRY_ADMIN_KEY` is not in the secret, the admin password is cleared on every start.

## Troubleshooting

1. **Pod restarts under heavy sessions**

   - **Cause**: `NODE_OPTIONS=--max-old-space-size` exceeds the container memory limit, so the kernel OOM-kills the process before Node's heap limit is hit.
   - **Fix**: Keep `--max-old-space-size` below the memory limit in `values.yaml`, leaving headroom for off-heap memory.

## References

- [felddy/foundryvtt-docker](https://github.com/felddy/foundryvtt-docker)
- [Foundry VTT installation](https://foundryvtt.com/article/installation/)
