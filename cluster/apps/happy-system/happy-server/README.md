# happy-server - Self-hosted Happy relay

## Overview

Relay between the [Happy](https://github.com/slopus/happy) phone/web app and the `happy` CLI in Coder workspaces, replacing Happy's public server ([#3314](https://github.com/anthony-spruyt/spruyt-labs/issues/3314)). Messages are end-to-end encrypted; the server stores blobs it can't read. Upstream publishes no image, so `ghcr.io/anthony-spruyt/happy-server` is built from the
`happy-server-self-host` npm package in [container-images](https://github.com/anthony-spruyt/container-images/tree/main/happy-server). It runs standalone: embedded PGlite and local files on the `/data` PVC, no Postgres, Redis or S3.

## Prerequisites

- Public hostname `happy` in `local.tunnel_routes` of [`infra/terraform/cloudflare/tunnel.tf`](../../../../infra/terraform/cloudflare/tunnel.tf). The app talks to the server directly, so the route has no Authentik forward auth.

## Operations

### Pointing the app at this server

In the Happy app, open **Server Configuration** and set the server URL to `https://happy.<external-domain>`, then sign out and back in. This server has its own accounts: an account from the public server doesn't exist here, and every workspace must pair again (see [Happy template keys](../../coder-workspaces/coder-workspaces/README.md#happy-template-keys)).

Workspaces get `HAPPY_SERVER_URL` from the Coder templates, which derive it from the Coder access URL (`code.` becomes `happy.`). A host alias sends it straight to Traefik instead of through Cloudflare.

### Master secret

`HANDY_MASTER_SECRET` signs every client token. External Secrets generates it once (`master-secret-eso.yaml`, `CreatedOnce`, `Orphan`). Deleting the `happy-server-master-secret` Secret generates a new one, which logs out every device and workspace.

### Signup

Signup is open to anyone who can reach the URL. Cloudflare's firewall rules limit that to Australian IPs and block bots.

## Troubleshooting

1. **Workspace daemon fails to authenticate after the switch**
   - **Cause**: `~/.happy/access.key` was paired against Happy's public server.
   - **Fix**: Run `happy auth logout`, then `happy` to pair again by QR. For template keys, rotate the `coder-happy-<template>` secret.

## References

- [Happy server self-hosting](https://github.com/slopus/happy/tree/main/packages/happy-server)
