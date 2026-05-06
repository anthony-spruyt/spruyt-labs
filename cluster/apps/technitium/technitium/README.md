# Technitium - DNS Server

## Overview

Technitium serves as the primary DNS server for internal domain resolution, providing reliable and configurable DNS services for the homelab environment.

## Prerequisites

- Persistent storage for DNS zone data
- Authentik OIDC provider configured (blueprint: `technitium-sso.yaml`)

## Single Sign-On (SSO)

Technitium v15+ supports OIDC SSO via Authentik. Both primary and secondary instances share a single Authentik OIDC provider with separate redirect URIs.

### Architecture

```text
Browser -> Technitium UI -> Authentik (auth.${EXTERNAL_DOMAIN}) -> OIDC callback -> Technitium
```

- **Authentik provider**: `Technitium` (blueprint-managed)
- **Redirect URIs**: `https://dns.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`, `https://dns-secondary.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`
- **Access control**: Authentik `Technitium Users` group
- **ExternalSecret**: Syncs OIDC credentials from `authentik-system` -> `technitium` namespace

### Important: Config Persistence

Technitium reads environment variables **only on first startup**. After that, config is persisted to PVC and env vars are ignored. This means:

- SSO must be configured via the **Technitium admin UI** (Settings -> SSO) on each instance
- Env vars in `values.yaml` serve as fallback for fresh PVC provisioning only
- If the PVC is deleted/recreated, SSO will auto-configure from env vars on first boot

### Secret Rotation: NOT Automated

Technitium is **excluded** from the weekly `oauth-secret-rotation` CronJob because:

1. Rotation updates Authentik + K8s secrets, then Reloader restarts the pod
1. Technitium ignores env vars on restart, reads old secret from PVC
1. Result: Authentik has new secret, Technitium has old -> SSO breaks

**To manually rotate the Technitium OIDC client secret:**

1. Generate a new secret
1. Update the Authentik provider via API or admin UI
1. Update the `authentik-technitium-oauth` secret in `authentik-system` namespace
1. Update SSO settings in **both** Technitium instances via their admin UIs
1. Verify SSO login works on both instances

## Troubleshooting

1. **SSO button not appearing**

   - SSO must be enabled via Technitium admin UI, not just env vars
   - Verify Settings -> SSO -> "Enable Single Sign-On" is checked

1. **SSO login fails with redirect error**

   - Verify redirect URI in Authentik matches exactly: `https://dns.lan.${EXTERNAL_DOMAIN}:53443/sso/callback`
   - Check Authentik provider has both redirect URIs (primary + secondary)

1. **SSO login fails with invalid client**

   - Client secret may have been rotated -- check current value in `technitium-oauth-credentials` secret matches what Technitium has in its config
   - Re-enter credentials in Technitium UI if needed

## References

- [Technitium Documentation](https://technitium.com/dns/)
