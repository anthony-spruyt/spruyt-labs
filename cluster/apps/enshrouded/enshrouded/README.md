# Enshrouded - Dedicated Game Server

## Overview

Enshrouded 1.0 dedicated server (Steam app 2278520) named `Ember Kelmire`, run with the [`mornedhels/enshrouded-server`](https://github.com/mornedhels/enshrouded-server) image. The image runs the Windows server under Proton and handles the steamcmd download, scheduled updates and save backups. Swap to a native Linux server once Keen ships one.

The server is a single StatefulSet replica with a `LoadBalancer` Service on UDP 15637 (`${ENSHROUDED_IP4}`). It is IPv4 only and has no web UI or HTTP endpoint.

## Joining

- **In-game Join list**: the server shows up under its name.
- **Direct**: choose "Search by IPv4 / Domain" and enter `enshrouded.<domain>` (the public domain), then the role password.

Remote players need the router port forward: UDP 15637 to `${ENSHROUDED_IP4}`. That forward lives on the router, not in this repo. On the LAN the name resolves through the Technitium record that external-dns writes from the Service annotation; outside it resolves through the DNS-only Cloudflare record from `infra/terraform/cloudflare/dns.tf`. Cloudflare Tunnel cannot carry UDP.

## Roles

The role a player gets is decided by the password they enter. The four groups mirror the game's native presets (Keen's [Server Roles Configuration](https://enshrouded.zendesk.com/hc/en-us/articles/19191581489309)). All groups can fight, loot, explore and progress in the world.

| Index | Role    | Kick/ban | Inventories | Edit world | Edit base | Extend base | Reserved slots |
| ----- | ------- | -------- | ----------- | ---------- | --------- | ----------- | -------------- |
| 0     | Admin   | yes      | yes         | yes        | yes       | yes         | 1              |
| 1     | Friend  | no       | yes         | yes        | yes       | yes         | 3              |
| 2     | Guest   | no       | no          | yes        | no        | no          | 0              |
| 3     | Visitor | no       | no          | no         | no        | no          | 0              |

Permissions are set through `SERVER_ROLE_<index>_*` variables in `app/values.yaml`. The image applies them to `enshrouded_server.json` on every start, so changes in Git take effect on the next pod restart (Reloader restarts it when the Secret changes).

### Passwords

Passwords come from the SOPS Secret `enshrouded-secrets` (`app/enshrouded-secrets.sops.yaml`) and are read with `secretKeyRef`:

| Role    | Secret key    |
| ------- | ------------- |
| Admin   | `ADMIN_PWD`   |
| Friend  | `FRIEND_PWD`  |
| Guest   | `GUEST_PWD`   |
| Visitor | `VISITOR_PWD` |

## Operations

### First start

On an empty game PVC the pod downloads the game (about 30 GB) before the server starts, so the startup probe allows up to 60 minutes. Follow progress with `kubectl -n enshrouded logs statefulset/enshrouded -f`.

### Updates

`UPDATE_CRON` checks Steam every 30 minutes. With `UPDATE_CHECK_PLAYERS` on, an update waits until nobody is connected. To force one: `kubectl -n enshrouded exec statefulset/enshrouded -- supervisorctl start enshrouded-force-update`.

### Storage and backups

Two PVCs split re-downloadable game files from the world saves, so Velero only backs up what cannot be re-created.

| PVC                | Size  | Mount                   | Holds                                                                          | Velero |
| ------------------ | ----- | ----------------------- | ------------------------------------------------------------------------------ | ------ |
| `enshrouded-game`  | 60 Gi | `/opt/enshrouded`       | Game files, `server/enshrouded_server.json`, `server/logs/`, `server/backups/` | no     |
| `enshrouded-saves` | 5 Gi  | `/opt/enshrouded-saves` | World saves (`SERVER_SAVE_DIR`)                                                | yes    |

- **Velero**: only `enshrouded-saves` carries `velero.io/backup-volumes: "true"`.
- **Hourly save backups**: the image zips the world files into `/opt/enshrouded/server/backups` on the game PVC (`BACKUP_CRON`), keeping the newest 48 (`BACKUP_MAX_COUNT`). These are not in Velero, so they do not survive losing that PVC.
- **Losing the game PVC**: the pod re-downloads the game on the next start (see First start). Saves are untouched; server settings and roles are re-applied from `app/values.yaml`, but in-game bans stored in `enshrouded_server.json` are lost.
- **Restoring a save backup**: scale the StatefulSet to 0, mount `enshrouded-saves` in a temporary pod, extract the zip into it, delete the pod and scale back up. The image resets file ownership on every start.

## Troubleshooting

- **Pod Running but not Ready**: the server program is not in the supervisord `RUNNING` state. During the first download or an update this is normal; otherwise check the logs.
- **`state is 0x202 after update job`**: file permission or disk space problem under `/opt/enshrouded`; see the image's Known Issues.

## References

- [Image README](https://github.com/mornedhels/enshrouded-server)
- [Server roles](https://github.com/mornedhels/enshrouded-server/blob/main/docs/SERVER_ROLES.md)
- [Keen server configuration](https://enshrouded.zendesk.com/hc/en-us/articles/16055441447709)
