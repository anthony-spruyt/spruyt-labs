# Enshrouded - Dedicated Game Server

## Overview

Enshrouded 1.0 dedicated server (Steam app 2278520), run with the [`mornedhels/enshrouded-server`](https://github.com/mornedhels/enshrouded-server) image. The image runs the Windows server under Wine (the `-wine` tag) and handles the steamcmd download, scheduled updates and save backups. It is the Wine build because on the Proton build the server never offers players a direct connection, so even
LAN players go through Steam's relays ([mornedhels/enshrouded-server#202](https://github.com/mornedhels/enshrouded-server/issues/202)). Swap to a native Linux server once Keen ships one.

The game server is IPv4 only and UDP only. Cloudflare Tunnel cannot carry UDP, so players reach it through a `LoadBalancer` Service instead of Traefik. The only HTTP endpoint is the live map (see Live map), which has its own Service and route.

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

Players pick the server from the in-game Join list, or choose "Search by IPv4 / Domain" and enter `enshrouded.${EXTERNAL_DOMAIN}`, then the role password. Players on the home LAN connect directly; everyone else joins through Steam's relays.

### Live map

`https://enshrouded-map.${EXTERNAL_DOMAIN}` shows online players, Flame Altars, fog, weather and time. It is [oggii/enshrouded-livemap](https://github.com/oggii/enshrouded-livemap): a DLL the game loads in place of the system `iphlpapi.dll`, which serves the map over HTTP from inside the game process on TCP 15637. Every request needs the `?key=` from `livemap.ini`. When a player joins, the game
announces the link with the key in chat.

Traefik routes the host to the `enshrouded-map` Service, and the Cloudflare Tunnel route is in `infra/terraform/cloudflare/tunnel.tf`. Outside the LAN only visitors in Australia can open it, and the map serves at most 32 open pages at once.

The image runs `BOOTSTRAP_HOOK` after Wine boots and before the server starts. The hook is `app/livemap-install.sh`, mounted from a ConfigMap at `/opt/livemap`:

- It downloads the release for `LIVEMAP_VERSION`, checks it against `LIVEMAP_SHA256`, and copies `iphlpapi.dll` next to the server executable and the web files into `livemap/`.
- It rewrites `livemap.ini` on every start. `Key=` is `LIVEMAP_KEY`, the key from the Secret `enshrouded-livemap-key`. If `LIVEMAP_KEY` is empty or the map would reject it, the hook keeps the existing `Key=`, or makes a new one when there is none. The Secret is optional, so the server still starts while it is missing.
- It always exits 0 and is capped at 300 s, so a map problem never stops the server from starting. `WINEDLLOVERRIDES=iphlpapi=n,b` is what makes Wine load the DLL.

The DLL, `livemap.ini` and `livemap.log` live on the game PVC under `/opt/enshrouded/server`. The `livemap/` folder is a subPath of the saves PVC, so Velero backs up the map history (`finds.json`, `discovered.json`, `explored.json`).

Renovate moves `LIVEMAP_VERSION` and `LIVEMAP_SHA256` together. A download or hash failure keeps the last good install and logs one line in the pod log. Shipped files in `livemap/` are replaced on each bump, so don't hand-edit them; the history files are kept.

The key is the Secret `enshrouded-livemap-key`, which External Secrets generates once (`app/livemap-key-eso.yaml`: `CreatedOnce`, `Orphan`, immutable). It stays the same when the game PVC is rebuilt and changes only when you rotate it. Share the link once in the friends' group chat so it's clickable.

To rotate the key, delete the Secret and its ExternalSecret, let Flux recreate the ExternalSecret, then restart the pod. External Secrets does not regenerate a deleted Secret on its own, and Reloader does not fire on a recreated one. Every shared link stops working.

```bash
kubectl -n enshrouded delete secret enshrouded-livemap-key
kubectl -n enshrouded delete externalsecret enshrouded-livemap-key
flux reconcile kustomization enshrouded -n flux-system
kubectl -n enshrouded wait --for=condition=Ready externalsecret/enshrouded-livemap-key --timeout=2m
kubectl -n enshrouded rollout restart statefulset/enshrouded
```

To roll back, revert every commit that references #3892 (`git log --grep '#3892'`): reverting the script without its tests fails the bats job. Removing only `WINEDLLOVERRIDES` also works: Wine then loads its own `iphlpapi` and the DLL does nothing. A failed rollout only self-remediates after the 70m HelmRelease timeout, so don't wait for it.

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

### CPU pinning

The server runs on the performance cores only. The worker CPUs are hybrid: logical CPUs 0-7 are performance cores and 8-15 are efficiency cores. Unpinned, about half of the game thread work landed on the efficiency cores, and pinning cut the minutes with a tick of 40 ms or more from 35% to 10% with the same average load.

The container `command` in `app/values.yaml` starts the image bootstrap under `taskset`, with the CPU list read from `/sys/devices/cpu_core/cpus` at container start. If that file is missing or empty it starts the bootstrap unpinned. The pin has to be there from the first process: Wine gives every thread and child process the CPU mask the first process had at startup, so pinning a running server
leaves its new threads on every core.

The `command` copies the image `CMD` (`/usr/local/etc/enshrouded/bootstrap`). An image update that changes the `CMD` must update the `command` too.

To check the pin, compare the performance-core list with the CPU mask of every thread of the server process. Take the PID of the `enshrouded_server` process from the `ps` output; every thread must show the performance-core list, including threads Wine creates after a player logs in:

```bash
kubectl -n enshrouded exec statefulset/enshrouded -- cat /sys/devices/cpu_core/cpus
kubectl -n enshrouded exec statefulset/enshrouded -- ps axww
kubectl -n enshrouded exec statefulset/enshrouded -- sh -c 'grep -h Cpus_allowed_list /proc/<pid>/task/*/status | sort | uniq -c'
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
4. **A LAN player goes through the relay**
   - **Cause**: the PC's Steam IP-sharing setting does not allow the direct connection, or the PC is on a network other than the LAN.
   - **Fix**: check both: try the Steam IP-sharing setting that always shares the IP, and confirm the PC is on the LAN network.

## References

- [Image README](https://github.com/mornedhels/enshrouded-server)
- [Server roles](https://github.com/mornedhels/enshrouded-server/blob/main/docs/SERVER_ROLES.md)
- [Keen server configuration](https://enshrouded.zendesk.com/hc/en-us/articles/16055441447709)
