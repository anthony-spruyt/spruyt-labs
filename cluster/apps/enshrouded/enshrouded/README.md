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

`https://enshrouded-map.${EXTERNAL_DOMAIN}` shows online players, Flame Altars, fog, weather and time. It is a DLL from [anthony-spruyt/enshrouded-livemap](https://github.com/anthony-spruyt/enshrouded-livemap), a fork of [oggii/enshrouded-livemap](https://github.com/oggii/enshrouded-livemap) that builds, checks and releases compatibility updates for new server builds.
The game loads it in place of the system `iphlpapi.dll`, and it serves the map over HTTP from inside the game process on TCP 15637. Every request needs the `?key=` from `livemap.ini`. When a player joins, the game announces the link with the key in chat.

Traefik routes the host to the `enshrouded-map` Service, and the Cloudflare Tunnel route is in `infra/terraform/cloudflare/tunnel.tf`. Outside the LAN only visitors in Australia can open it, and the map serves at most 32 open pages at once.

The image runs `BOOTSTRAP_HOOK` after Wine boots and before the server starts. The hook is `app/livemap-install.sh`, mounted from a ConfigMap at `/opt/livemap`:

- It downloads the release for `LIVEMAP_VERSION` from the fork, `anthony-spruyt/enshrouded-livemap` (the repo is fixed in the script), checks it against `LIVEMAP_SHA256`, and copies `iphlpapi.dll` next to the server executable and the web files into `livemap/`.
  The two values are the pin in `app/livemap-pin.yaml`, which reaches the pod as the ConfigMap `enshrouded-livemap-pin` mounted at `/opt/livemap-pin`. Only a version shaped `vX.Y.Z` and a lowercase 64 digit hash are used; the hook logs a fixed line for any other value and installs nothing. A bad-listed version (see Updating the live map) is never installed.
- It checks `livemap/index.html` on every start and, while it still has the empty page icon upstream ships, inlines the Flame Altar icon from the release in its place, so the browser tab has an icon without a request that would need the key. It does nothing once upstream ships its own icon.
- It rewrites `livemap.ini` on every start. `Key=` is `LIVEMAP_KEY`, the key from the Secret `enshrouded-livemap-key`. If `LIVEMAP_KEY` is empty or breaks the map's key rule (3-64 letters, digits, `-` or `_`, and not a reserved word), the hook keeps the existing `Key=`, or makes a new one when there is none. When it ignores a key that is set, it logs why, without the key. The Secret is optional,
  so the server still starts while it is missing.
- It adds one line to the image crontab (the image rewrites the crontab on every start, so the hook adds it again each time) that runs the same script with `--cron` every 5 minutes, off the updater's minutes.
- It always exits 0 and is capped at 300 s, so a map problem never stops the server from starting. `WINEDLLOVERRIDES=iphlpapi=n,b` is what makes Wine load the DLL.

The DLL, `livemap.ini` and `livemap.log` live on the game PVC under `/opt/enshrouded/server`. The `livemap/` folder is a subPath of the saves PVC, so Velero backs up the map history (`finds.json`, `discovered.json`, `explored.json`).

The key is the Secret `enshrouded-livemap-key`, which External Secrets generates once (`app/livemap-key-eso.yaml`: `CreatedOnce`, `Orphan`, immutable). It stays the same when the game PVC is rebuilt and changes only when you rotate it. Share the link once in the friends' group chat so it's clickable.

To rotate the key, delete the Secret and its ExternalSecret, let Flux recreate the ExternalSecret, then restart the pod. External Secrets does not regenerate a deleted Secret on its own, and Reloader does not fire on a recreated one. Every shared link stops working.

```bash
kubectl -n enshrouded delete secret enshrouded-livemap-key
kubectl -n enshrouded delete externalsecret enshrouded-livemap-key
flux reconcile kustomization enshrouded -n flux-system
kubectl -n enshrouded wait --for=condition=Ready externalsecret/enshrouded-livemap-key --timeout=2m
kubectl -n enshrouded rollout restart statefulset/enshrouded
```

If the map breaks a rollout, switch it off by removing `WINEDLLOVERRIDES`: Wine then loads its own `iphlpapi` and the DLL does nothing. A failed rollout only self-remediates after the HelmRelease timeout, so don't wait for it.

#### Updating the live map

Renovate bumps the pin: it moves `LIVEMAP_VERSION` and `LIVEMAP_SHA256` together in `app/livemap-pin.yaml` from the fork's releases. Reloader watches only the two Secrets, so a bump does not restart the pod; the cron job picks it up. Shipped files in `livemap/` are replaced on each bump, so don't hand-edit them; the history files are kept.

The agent-platform worker also reads `LIVEMAP_VERSION` from this file on `main` (`Livemap__PinPath` in `cluster/apps/agent-platform/worker/app/values.yaml`) to learn which builds the live map already covers. The web role sets the same value (`cluster/apps/agent-platform/web/app/values.yaml`) and only checks it at startup. Moving or renaming the file needs the value changed in both files.

Every run of `--cron` reads the pin from the mounted file (cron has no container environment), never rewrites `livemap.ini`, always exits 0 and is capped at 40 min. The rule is: a map that works stays on, and a map that crashes the server stays off until a newer version is pinned. Each run does three things:

- It logs `livemap-status: state=<active|inactive|disabled|off> version=<v> build=<b>` to the pod log, taken from `livemap.log` and the game build in `/opt/enshrouded/current_version`. `inactive` means the DLL does not know the running game build and hooks nothing. `off` means the DLL is not installed (turned off after a crash, see below).
- It compares the server's pid and start time with the ones it recorded last run (kept in `/tmp` with the size of `/var/log/supervisor/supervisord.log`, so a pod start begins anew).
  A change nobody planned is a crash with the report and decision below.
  Planned: a `stopped:` line for the server in supervisord's log since the last run (an unplanned exit logs `exited:` instead, and a stop excuses a server that is up or starting, never one that is down), the image updater, a game build change,
  the image's restart jobs (`enshrouded-restart`, `-force-update`, `-reset-roles`), our own swap restart and a pod start.
- A server in `STARTING` or `EXITED` that was up at the last run is a crash. A server in `BACKOFF` or `FATAL` is a crash when it was up at the last run, and counts once per container when there is no record:
  the first run writes the marker `/tmp/livemap-fatal` and later runs of that container count nothing more. A restarted container loses the marker, so a crash loop that restarts the container still adds up to the second crash.
  A server that is `STOPPING` or `STOPPED` is no verdict. Nothing counts while the updater or a restart job runs.
- The report reads the run that crashed, which is the last one the DLL started by the time the server was last seen (plus 5 s, because the DLL stamps its start line a moment after the server is `RUNNING`), not the run that has just started.
- It swaps in the pinned release when that differs from the installed one and the version is not on the bad list. It skips while another run holds its lock, while the image updater or a restart job runs, while the server is not `RUNNING` or when it just handled a crash. It checks that the server is `RUNNING` with nothing planned running again after the download and before it installs and restarts.

A crash is never read from `crash_dumps/` (dumps also appear on slow planned stops, [mornedhels/enshrouded-server#265](https://github.com/mornedhels/enshrouded-server/issues/265)).
Every unplanned crash logs one line, `livemap-crash: version=<v> build=<b> dump=<new file name or none> count=<n> decision=<off|stays-on> fault=<FAULT line or none>`; `count` is the crashes of that version in the last 24 h.

The map turns off only when the decision is `off`: the DLL logged a `[livemap] FAULT` line in `livemap.log` for the run that crashed, or the same version crashed the server a second time within 24 h.
One function, `crash_decision`, holds that rule. Planned stops never count, even when the game writes a dump while stopping.

Turning the map off adds the installed version to the bad list, removes `iphlpapi.dll` and logs `state=off`. It restarts the server to unload the map only when `checkServerEmpty` says nobody is on; otherwise the next restart does. A bad-listed version is never installed again, at pod start or by the cron job; a newer pinned version installs as usual.

A swap goes like this:

1. Download the release and check its hash into a staging folder. Players on the server at the start or after the download (checked with the image's `checkServerEmpty`) leave everything as it was, and the next run tries again. An image without `checkServerEmpty` counts as a server that is not empty.
2. Install the new files and restart `enshrouded-server` with `supervisorctl` (allow up to 180 s: the stop alone takes about a minute).
3. Watch the server for 10 min once it is `RUNNING` again. If it stops being `RUNNING` or restarts, that is a crash and the report and decision above apply. If the updater or a restart job ran, the game build changed or supervisord logged a stop for the server during the watch, there is no verdict.

The bad list and the crash history live on the game PVC in `/opt/enshrouded/livemap-state`: `bad-list` holds one version per line and `crashes` one `<epoch> <version>` line per crash of the last 24 h. There is no rollback to an older map. To turn the map back on without a new release, remove the version from `bad-list` and the next run installs the pinned one again.

```bash
kubectl -n enshrouded exec statefulset/enshrouded -- cat /opt/enshrouded/livemap-state/bad-list
kubectl -n enshrouded exec statefulset/enshrouded -- rm /opt/enshrouded/livemap-state/bad-list
kubectl -n enshrouded logs statefulset/enshrouded | grep -E 'livemap-(install|status|crash)'
```

A download or hash failure keeps the installed release and logs one `livemap-install` line. The `LivemapInactive` alert fires when the server runs for 4 h and the status is never `active` (a new game build the fork has not released a fix for yet, or a map turned off after a crash), and `LivemapStatusMissing` fires after the pod logged no status line for 60 to 90 min (the cron job is not running).

### Updates

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
