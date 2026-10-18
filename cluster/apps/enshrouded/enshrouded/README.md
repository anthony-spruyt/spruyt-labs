# Enshrouded - Dedicated Game Server

## Overview

Enshrouded 1.0 dedicated server (Steam app 2278520), run with the [`mornedhels/enshrouded-server`](https://github.com/mornedhels/enshrouded-server) image. The image runs the Windows server under Proton and handles the steamcmd download, scheduled updates and save backups. Swap to a native Linux server once Keen ships one.

The server is IPv4 only, UDP only, and has no web UI or HTTP endpoint. Cloudflare Tunnel cannot carry UDP, so players reach it through a `LoadBalancer` Service instead of Traefik.

## Prerequisites

- **Router port forward**: UDP 15637 to the Service's LoadBalancer IP (`ENSHROUDED_IP4`). It lives on the router, not in this repo; remote players cannot join without it.
- **DNS**: `enshrouded.${EXTERNAL_DOMAIN}` resolves through the Technitium record that external-dns writes from the Service annotation on the LAN, and through the DNS-only Cloudflare record in `infra/terraform/cloudflare/dns.tf` outside it.
- **Secret**: `enshrouded-secrets` (`app/enshrouded-secrets.sops.yaml`) holds one password per role, read with `secretKeyRef` in `app/values.yaml`.

## Operations

### Roles

The role a player gets is decided by the password they enter. The four roles mirror the game's native presets (Keen's [Server Roles Configuration](https://enshrouded.zendesk.com/hc/en-us/articles/19191581489309)); the permissions are the `SERVER_ROLE_<index>_*` variables in `app/values.yaml`. Keen's page gives edit-world only in prose, so it is derived from that: only Visitor is barred from
changing the world outside the base. The image applies the roles to `enshrouded_server.json` on every start, so a Git change takes effect on the next pod restart (Reloader restarts it when the Secret changes).

### Joining

Players pick the server from the in-game Join list, or choose "Search by IPv4 / Domain" and enter `enshrouded.${EXTERNAL_DOMAIN}`, then the role password.

### Updates

With `UPDATE_CHECK_PLAYERS` on, an update waits until nobody is connected. To force one: `kubectl -n enshrouded exec statefulset/enshrouded -- supervisorctl start enshrouded-force-update`.

### Storage and backups

Two PVCs split re-downloadable game files from the world saves, so Velero only backs up what cannot be re-created. Only the saves PVC carries the Velero opt-in label.

- **Save zips**: the image writes its scheduled save zips into the game PVC (`BACKUP_CRON`), so Velero does not cover them and they do not survive losing that PVC.
- **Losing the game PVC**: the pod re-downloads the game on the next start. Saves are untouched; server settings and roles are re-applied from `app/values.yaml`, but in-game bans stored in `enshrouded_server.json` are lost.
- **First start**: on an empty game PVC the download takes long enough that the startup probe, the HelmRelease and the Flux Kustomization timeouts are all raised. Follow progress with `kubectl -n enshrouded logs statefulset/enshrouded -f`.
- **Restoring a save zip**: scale the StatefulSet to 0, mount the saves PVC in a temporary pod, extract the zip into it, delete the pod and scale back up. The image resets file ownership on every start.

## Troubleshooting

1. **Pod Running but not Ready**
   - **Cause**: the server program is not in the supervisord `RUNNING` state. During the first download or an update this is normal.
   - **Fix**: otherwise check the logs for the reason the server program stopped.
2. **`state is 0x202 after update job`**
   - **Cause**: file permission or disk space problem under `/opt/enshrouded`.
   - **Fix**: see Known Issues in the image README.

## References

- [Image README](https://github.com/mornedhels/enshrouded-server)
- [Server roles](https://github.com/mornedhels/enshrouded-server/blob/main/docs/SERVER_ROLES.md)
- [Keen server configuration](https://enshrouded.zendesk.com/hc/en-us/articles/16055441447709)
