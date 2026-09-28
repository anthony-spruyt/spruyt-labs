# flux-receivers - GitHub Push Webhook

## Overview

A `Receiver` that makes Flux reconcile the `flux-system` GitRepository on every push to GitHub, instead of waiting for the 1h sync interval. This is why pushes to `main` deploy within seconds.

## Prerequisites

- **GitHub repository webhook** (repo Settings -> Webhooks), created by hand: content type `application/json`, event `push`, secret equal to the `token` in `app/github-webhook-secret.sops.yaml`.
- **Public route**: the `flux-webhook` entry in `infra/terraform/cloudflare/tunnel.tf` points the tunnel straight at the `webhook-receiver` Service, bypassing Traefik. cloudflared needs the matching egress rule in `cluster/apps/cloudflare-system/network-policies.yaml`.

## Operations

### Webhook URL

The path is `/hook/<sha256 digest>`, derived by notification-controller from the Receiver name, namespace and token. Read it from the Receiver status (`kubectl get receiver -n flux-system github-receiver`) and set the GitHub webhook URL to `https://flux-webhook.${EXTERNAL_DOMAIN}` plus that path.

### Rotating the token

Changing the token changes the digest, so the path changes too. Update the SOPS secret, wait for the Receiver to report the new path, then update both the secret and the URL on the GitHub webhook.

## Troubleshooting

1. **GitHub deliveries return 404 after a token change**
   - **Cause**: The GitHub webhook still uses the old `/hook/` path.
   - **Fix**: Copy the new path from the Receiver status into the webhook URL.

## References

- [Flux Receiver API](https://fluxcd.io/flux/components/notification/receivers/)
