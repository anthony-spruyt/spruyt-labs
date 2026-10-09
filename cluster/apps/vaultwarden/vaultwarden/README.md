# Vaultwarden - Password Manager

## Overview

Household Bitwarden-compatible password manager, exposed publicly through the Cloudflare Tunnel so clients work off-LAN. Login is Authentik SSO (OpenID Connect).

## Prerequisites

- Cloudflare Tunnel route `vaultwarden` in `infra/terraform/cloudflare/tunnel.tf`.
- Authentik OAuth provider and secret — see the [authentik README](../../authentik-system/authentik/README.md) for the provider requirements Vaultwarden imposes (RS256 signing key, 10-minute access tokens, `offline_access`).

## Operations

- SSO client ID and secret come from `authentik-system` through the `vaultwarden-oauth-credentials` ExternalSecret and are rotated by the shared Authentik rotation job. Non-secret settings (domain, signups, SSO, push relay) are plain `env:` in `app/values.yaml`; only credentials stay in `vaultwarden-secrets` (SOPS). Changes made in the `/admin` panel are saved to `/data/config.json` and override
  these env values.
- Data is on the `vaultwarden-data-v2` PVC, labelled `velero.io/backup-volumes: "true"`. The Velero volume policy (`velero/velero/resources/volume-policy.yaml`) snapshots only labelled PVCs and skips everything else, so a replacement PVC without the label silently drops the vault from backups.

## References

- [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
- [Vaultwarden SSO](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect)
