# happy-server - Self-hosted Happy relay

## Overview

Relay between the [Happy](https://github.com/slopus/happy) phone/web app and the `happy` CLI in Coder workspaces, replacing Happy's public server ([#3314](https://github.com/anthony-spruyt/spruyt-labs/issues/3314)). Messages are end-to-end encrypted; the server stores blobs it can't read. Upstream publishes no image, so `ghcr.io/anthony-spruyt/happy-server` is built from the
`happy-server-self-host` npm package in [container-images](https://github.com/anthony-spruyt/container-images/tree/main/happy-server). It runs standalone: embedded PGlite and local files on the `/data` PVC, no Postgres, Redis or S3.

## Prerequisites

- Public hostname `happy` in `local.tunnel_routes` of [`infra/terraform/cloudflare/tunnel.tf`](../../../../infra/terraform/cloudflare/tunnel.tf). The app signs in with the server's own accounts, not through Authentik.

## Operations

### Pointing the app at this server

The app hides the server setting while signed in to the default server. Log out (**Settings → Account → Logout**), tap the gear at the top right of the welcome screen, set the server URL to `https://happy.<external-domain>`, then create an account on home Wi-Fi (see [Signup](#signup)). This server has its own accounts: an account from the public server doesn't exist here, and every workspace must
pair again (see [Happy template keys](../../coder-workspaces/coder-workspaces/README.md#happy-template-keys)).

The app's server check wants `/` to return the plain-text banner, which the server only sends when it isn't serving its bundled webapp ([slopus/happy#501](https://github.com/slopus/happy/issues/501)). An `emptyDir` hides the webapp, so there is no web UI and the CLI's browser login goes nowhere: pair by QR. Drop the mount once the app checks `/health` instead.

Workspaces get `HAPPY_SERVER_URL` from the Coder templates, which derive it from the Coder access URL (`code.` becomes `happy.`). A host alias sends it straight to Traefik instead of through Cloudflare.

### Master secret

`HANDY_MASTER_SECRET` signs every client token. External Secrets generates it once (`master-secret-eso.yaml`, `CreatedOnce`, `Orphan`). Deleting the `happy-server-master-secret` Secret generates a new one, which logs out every device and workspace.

### Signup

`POST /v1/auth` both creates accounts and logs in. A Cloudflare rule in [`rulesets.tf`](../../../../infra/terraform/cloudflare/rulesets.tf) limits `/auth` paths from the internet to the token-checked approval endpoints and the read-only `/v1/auth/request/status`, so approving a workspace QR works on mobile data. A signed-in phone needs `/v1/auth` again only to
restore an account.

LAN DNS points the host at Traefik, so creating an account, restoring one, or adding a device works on home Wi-Fi only, with Private DNS or iCloud Private Relay off. Workspaces reach Traefik through their host alias and are unaffected.

## Troubleshooting

1. **Workspace daemon fails to authenticate after the switch**
   - **Cause**: `~/.happy/access.key` was paired against Happy's public server.
   - **Fix**: Run `happy auth logout`, then `happy` to pair again by QR. For template keys, rotate the `coder-happy-<template>` secret.

## References

- [Happy server self-hosting](https://github.com/slopus/happy/tree/main/packages/happy-server)
- [App server screen](<https://github.com/slopus/happy/blob/main/packages/happy-app/sources/app/(app)/server.tsx>)
