# Enshrouded - Dedicated Game Server

## Overview

Enshrouded 1.0 dedicated server (Steam app 2278520), run with the [`mornedhels/enshrouded-server`](https://github.com/mornedhels/enshrouded-server) image. The image runs the Windows server under Wine (the `-wine` tag) and handles the steamcmd download, scheduled updates and save backups. It is the Wine build because on the Proton build the server never offers players a direct connection, so even
LAN players go through Steam's relays ([mornedhels/enshrouded-server#202](https://github.com/mornedhels/enshrouded-server/issues/202)). Swap to a native Linux server once Keen ships one.

The server is IPv4 only, UDP only, and has no web UI or HTTP endpoint. Cloudflare Tunnel cannot carry UDP, so players reach it through a `LoadBalancer` Service instead of Traefik.

## Prerequisites

- **Router port forward**: none. Players join through Steam's relays, so the server needs no inbound port from the internet. Forward UDP 15637 to the Service's LoadBalancer IP (`ENSHROUDED_IP4`) on the router only if a remote player can't connect through the relays.
- **DNS**: `enshrouded.${EXTERNAL_DOMAIN}` resolves through the Technitium record that external-dns writes from the Service annotation on the LAN, and through the DNS-only Cloudflare record in `infra/terraform/cloudflare/dns.tf` outside it.
- **Secret**: `enshrouded-secrets` (`app/enshrouded-secrets.sops.yaml`) holds one password per role, read with `secretKeyRef` in `app/values.yaml`.

## Operations

### Roles

The role a player gets is decided by the password they enter. The four roles mirror the game's native presets (Keen's [Server Roles Configuration](https://enshrouded.zendesk.com/hc/en-us/articles/19191581489309)); the permissions are the `SERVER_ROLE_<index>_*` variables in `app/values.yaml`. Keen's page gives edit-world only in prose, so it is derived from that: only Visitor is barred from
changing the world outside the base. The image applies the roles to `enshrouded_server.json` on every start, so a Git change takes effect on the next pod restart (Reloader restarts it when the Secret changes).

### Difficulty

The game settings are the `SERVER_GS_*` variables in `app/values.yaml`. Every rollout rewrites them in the game config, so a Git change takes effect on the next pod restart. Only the preset applies on its own; the other knobs apply only with preset `Custom`. To change a knob, edit its value. Don't delete the line: a removed variable keeps its last value in the game config.

### Joining

Players pick the server from the in-game Join list, or choose "Search by IPv4 / Domain" and enter `enshrouded.${EXTERNAL_DOMAIN}`, then the role password.

### Updates

With `UPDATE_CHECK_PLAYERS` on, an update should wait until nobody is connected. On image 1.8.0 the player check always reads an empty server, so updates kick connected players ([mornedhels/enshrouded-server#260](https://github.com/mornedhels/enshrouded-server/issues/260); drop this note once the image with the fix from #261 is deployed).

To force an update:

```bash
kubectl -n enshrouded exec statefulset/enshrouded -- supervisorctl start enshrouded-force-update
```

It deletes the steamcmd manifests in `/opt/enshrouded/server/steamapps` and runs the updater, which stops the server, re-checks every game file, downloads the latest build and starts the server again. Connected players are kicked. The saves PVC and the save zips are not touched. The server is back in about a minute; follow it with `kubectl -n enshrouded logs statefulset/enshrouded -f`.

Compare the installed build with Steam's latest; they match once the update is done:

```bash
kubectl -n enshrouded exec statefulset/enshrouded -- grep '"buildid"' /opt/enshrouded/server/steamapps/appmanifest_2278520.acf
curl -s https://api.steamcmd.net/v1/info/2278520 | jq -r '.data["2278520"].depots.branches.public.buildid'
```

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
3. **Game says the server version is too old**
   - **Cause**: the updater restarted the server, but steamcmd reported `already up to date` and installed nothing, so the server came back on the old build. Seen on the first update after a pod restart, when steamcmd's app cache (kept outside the PVCs) is empty ([mornedhels/enshrouded-server#262](https://github.com/mornedhels/enshrouded-server/issues/262)).
   - **Fix**: compare the builds and force an update (see Updates).

## References

- [Image README](https://github.com/mornedhels/enshrouded-server)
- [Server roles](https://github.com/mornedhels/enshrouded-server/blob/main/docs/SERVER_ROLES.md)
- [Keen server configuration](https://enshrouded.zendesk.com/hc/en-us/articles/16055441447709)
