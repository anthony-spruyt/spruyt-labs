# UniFi OS Server — host facts and migration record

Reference for the `unifi-os-upgrade` skill. Host: `ssh unifi`. Recorded 2026-09-06 during the migration from the natively-installed UOS 4.2.23 to the containerised build on Docker.

Treat the host inventory below as established — do not re-discover it. The phase-by-phase log is kept because it documents _why_ the current setup looks the way it does, and what the fallback is.

**Current state:** UOS `5.1.40` via image tag `v1.6.0`, Docker Compose, bind mounts under `/srv/uos/`. The old 4.2.23 podman install is still on disk, stopped and disabled, as a fallback.

**Backups live on the workstation at `/home/aspruyt/uos-migration-backups/`, plus UniFi cloud's weekly automatic backups.** The Pi-side `/srv/migration-backups/` directory referenced in the Phase 1 log below **was deleted on 2026-09-06** once both copies were checksum-verified — a backup on the disk it protects against is not a backup. Historical Pi paths in this file are a record of what
happened, not current locations.

## Resolved variables

```text
OLD_INSTALLER=/home/aspruyt/<ubiquiti-installer>-linux-arm64-4.2.23-<uuid>-arm64  # glob for it
UNINSTALLER=/usr/local/bin/uosserver-purge      # NOT an installer subcommand
CURRENT_UOS_VERSION=4.2.23                      # container image 0.0.38
UOS_IMAGE_TAG=v1.6.0                            # ships UOS 5.1.40, arm64 manifest verified
```

## Phase 0 checklist results

| #   | Check                                 | Result                                                     |
| --- | ------------------------------------- | ---------------------------------------------------------- |
| 1   | cgroup v2 (`cgroup.controllers` test) | **PASS** — `cgroup v2 OK`                                  |
| 2   | Free space on `/`                     | **PASS** — `/dev/sda2` 235G, 9.6G used, **216G free**      |
| 3   | Native install located                | `uosserver.service`, rootless podman as user `uosserver`   |
| 4   | Current version                       | **4.2.23** (`server.conf`)                                 |
| 5   | Port holders                          | all held by `slirp4netns` pid 1324 (rootless podman netns) |
| 6   | Docker present?                       | **No** — `which docker` empty                              |
| 7   | Data dirs                             | 6 podman named volumes, 1.8G total (below)                 |
| 8   | Image tag proposal                    | `v1.6.0`                                                   |

## How the native install actually works

Not what the plan assumed. Key correction:

- `sudo podman ps -a` **as root is empty**. Podman runs **rootless as user `uosserver`** (uid 1001).

- systemd unit: `/etc/systemd/system/uosserver.service` → `ExecStart=/usr/local/bin/uosserver service`, `User=uosserver`, `WorkingDirectory=/var/lib/uosserver`, enabled, running since 2026-06-06.

- Helper PID: `/var/lib/uosserver/discovery`.

- Query podman with:

  ```bash
  sudo -u uosserver env HOME=/home/uosserver XDG_RUNTIME_DIR=/run/user/1001 podman ps -a
  ```

- Container: `5bfc4753ab11`, image `docker.io/library/uosserver:0.0.38`, **Up, healthy**.

- `/var/lib/uosserver/server.conf`:

  ```text
  CONTAINER_VERSION=0.0.38
  UOS_SERVER_VERSION=4.2.23
  CONTAINER_IMAGE_NAME=docker.io/library/uosserver:0.0.38
  UOS_UUID=<recorded on host, not reproduced here>
  ```

### Uninstall path (Phase 2 correction)

`uosserver` has **no `uninstall`/`remove` subcommand**. Its help lists: `start · stop · status · shell · support · version · help`, plus a separate note:

```text
Uninstall:
  uosserver-purge     Completely uninstall UOS Server (run as separate command)
```

So Phase 2 step 1–2 becomes `/usr/local/bin/uosserver-purge` (owned `uosserver:uosserver`, mode 755). Its exact behaviour is **unverified** — needs a `--help`/dry-run probe at Phase 2, and it very likely deletes the podman volumes. **Phase 1 tarball is mandatory before it runs.**

## Data directories (Phase 1 tarball source)

Podman rootless storage root: `/home/uosserver/.local/share/containers/storage` Volume path: `<storage>/volumes/<name>/_data`

| Volume                                       | Size     | Container path                  |
| -------------------------------------------- | -------- | ------------------------------- |
| `uosserver_var_lib_unifi`                    | 675M     | `/var/lib/unifi`                |
| `uosserver_var_lib_mongodb`                  | 496M     | `/var/lib/mongodb`              |
| `uosserver_persistent`                       | 295M     | `/persistent`                   |
| `uosserver_data`                             | 231M     | `/data`                         |
| `uosserver_var_log`                          | 85M      | `/var/log`                      |
| `uosserver_srv`                              | 20K      | `/srv`                          |
| **volumes total**                            | **1.8G** |                                 |
| `/home/uosserver` total (incl. image layers) | 4.0G     |                                 |
| `/var/lib/uosserver`                         | 3.3M     | binaries + `server.conf` + logs |

Proposed Phase 1 tarball paths:

```text
/home/uosserver/.local/share/containers/storage/volumes
/var/lib/uosserver
```

~1.8G of data → tarball comfortably fits in 216G free and copies to the workstation fine.

No `etc-rabbitmq-ssl` volume exists on 4.2.23. The compose file creates it empty — harmless.

## Ports

`ss -tulpn` (filtered to plan's list):

```text
tcp  0.0.0.0:11443   slirp4netns pid 1324
tcp  0.0.0.0:8080    slirp4netns pid 1324
udp  0.0.0.0:3478    slirp4netns pid 1324
udp  0.0.0.0:10003   slirp4netns pid 1324
```

Host `443` is **not** in use. But the running container publishes **more than the plan's compose file**:

```text
6789/tcp        mobile speedtest
8080/tcp        device inform          <- in plan
8444/tcp        secure hotspot
8880-8882/tcp   hotspot redirect
11443->443/tcp  web UI                 <- in plan
3478/udp        STUN                   <- in plan
5514/udp        remote syslog
10003/udp       device comms           <- in plan
```

**Decision needed at GATE 0** — the plan's compose only maps 4 of these 8. See below.

## Memory

```text
Mem:  3.7Gi total, 1.7Gi used, 2.0Gi available
Swap: 0B
```

Matches the plan. Swap still needed (Phase 3.5).

## Version jump

`4.2.23` → `5.1.40` (via image tag `v1.6.0`). Upstream release notes between them are CI/dependency churn plus rolling "Update UniFi OS Server to X" bumps:

| Tag               | UOS version | Notable                                                     |
| ----------------- | ----------- | ----------------------------------------------------------- |
| `4.3.6`           | 4.3.6       | last 4.x tag                                                |
| `5.0.6`           | 5.0.6       | first stable 5.x                                            |
| `v1.0.0`–`v1.2.0` | —           | repo switched to its own SemVer, decoupled from UOS version |
| `v1.3.0`          | 5.1.19      | fix lingering systemd-shutdown on container stop            |
| `v1.4.0`          | 5.1.21      | —                                                           |
| `v1.5.0`          | 5.1.37      | build moved to Ubuntu 26.04                                 |
| `v1.5.1`          | —           | `APP_MODEL` support                                         |
| `v1.6.0`          | **5.1.40**  | latest stable, published 2026-09-02                         |

No breaking-change or migration warnings in any release body. No `-ea` tags after `5.0.6-ea`.

Image verified on GHCR:

```text
ghcr.io/lemker/unifi-os-server:v1.6.0
  mediaType: application/vnd.oci.image.index.v1+json
  linux/amd64
  linux/arm64   <- present
```

## Phase 1 — Backups (complete)

Decisions taken at GATE 0: **map all 8 ports** (option A), **skip the GitHub issue**.

### Application backups

Downloaded via the UniFi cloud portal, Network v10.2.105.

| File                                 | Size     | Role                          |
| ------------------------------------ | -------- | ----------------------------- |
| `unifi_os_backup_<id>.unifi`         | 187280 B | **Primary** — full UOS backup |
| `network_site_Default_v10.2.105.unf` | 77136 B  | Secondary — site export       |

The `.unifi` file is the full UniFi OS backup and **contains the Network application data** — Phase 5 restores from it. The `.unf` is a site export, not a separate Network backup: Network 10.x folded the standalone `.unf` download into the UOS backup, so there is nothing else to obtain. Kept as a second artifact anyway.

Both present with **matching sha256** at:

- Pi: `/srv/migration-backups/`
- Workstation: `/home/aspruyt/uos-migration-backups/`

(`*:Zone.Identifier` files in the workstation dir are WSL download metadata — not copied, ignore.)

### Service stop (for a consistent tarball)

`systemctl stop uosserver.service` alone is **not sufficient** — it stops the supervisor but the rootless podman container keeps running and keeps holding the ports. Correct sequence:

```bash
sudo systemctl stop uosserver.service     # supervisor
sudo /usr/local/bin/uosserver stop        # the container itself
```

Result: container `Exited (0)`, all four ports released. UOS has been **left stopped** — Phase 2 removes it anyway.

### Native-data tarball

```bash
sudo tar czf /srv/migration-backups/native-data-2026-09-06.tar.gz -C / \
  home/uosserver/.local/share/containers/storage/volumes \
  var/lib/uosserver
```

Relative paths (`-C /`) so the archive has no leading `/` — restore is explicit, not accidental.

| Property           | Value                                                               |
| ------------------ | ------------------------------------------------------------------- |
| Size               | 912 422 090 B (912 MB, from 1.8 G source)                           |
| sha256             | recorded at the time; both copies matched                           |
| Pi copy            | `/srv/migration-backups/native-data-2026-09-06.tar.gz`              |
| Workstation copy   | `/home/aspruyt/uos-migration-backups/native-data-2026-09-06.tar.gz` |
| Checksums match    | **yes**, both copies identical                                      |
| `gzip -t`          | **OK**                                                              |
| Entries in archive | 4972                                                                |

Taken with the service stopped, so the mongo/postgres files are consistent.

**GATE 1 conditions: all met.**

## Phase 2 — REVISED: disable, do not delete (complete)

**Plan deviation, approved by the user.** The written Phase 2 runs `uosserver-purge` to remove the native install before Docker goes on. Disk is not scarce (215 G free) and the stopped container uses no RAM, so the old install is being **kept in place, stopped and disabled** until the new stack is proven in Phase 6.

This retroactively invalidates the Phase 1 note that "no image-level rollback exists":

|            | Written plan                       | Actual                                                  |
| ---------- | ---------------------------------- | ------------------------------------------------------- |
| Rollback   | reinstall 4.x + restore app backup | `compose down`, then `systemctl enable --now uosserver` |
| Time       | ~1 hour                            | ~1 minute                                               |
| Data state | restored from backup               | untouched, live                                         |

`uosserver-purge` is deferred until after Phase 6 passes — or never.

### The boot-time conflict (found and fixed)

`uosserver.service` was `enabled`, so any reboot would have restarted the old container and taken ports 8080 / 11443 / 3478 / 10003 away from Docker — which would have silently broken the Phase 6 reboot test. Fixed with:

```bash
sudo systemctl disable uosserver.service
# Removed '/etc/systemd/system/multi-user.target.wants/uosserver.service'
```

Nothing else can auto-start it — verified:

| Autostart vector                        | State                                                 |
| --------------------------------------- | ----------------------------------------------------- |
| `uosserver.service`                     | **disabled**, inactive                                |
| container restart policy                | `unless-stopped`, but container is explicitly stopped |
| `podman-restart.service`                | disabled                                              |
| `podman.socket`                         | disabled                                              |
| `/home/uosserver/.config/systemd/user/` | does not exist                                        |
| linger for `uosserver`                  | `yes` (harmless — nothing left for it to start)       |

### Verified clean state (GATE 2)

```text
uosserver.service   disabled / inactive
container           uosserver | Exited (0)
ports               ALL FREE  (11443 8080 3478 10003 443 6789 8444 8880-8882 5514)
memory              537Mi used, 3.2Gi available   (was 1.7Gi used while 4.x ran)
disk                215G free
```

**Standing rule for the rest of the migration: never run both stacks at once — they contend for the same ports. Confirm `uosserver` is down before every `docker compose up`.**

## Phase 3 — Docker (complete)

Docker's Ubuntu repo **does** carry `questing` — the plan's `docker.io` fallback was not needed. Verified before touching apt:

```text
https://download.docker.com/linux/ubuntu/dists/  → … oracular plucky questing resolute …
dists/questing/Release → HTTP 200
```

Installed via the official repo, `arch=arm64`, keyring at `/etc/apt/keyrings/docker.asc`, source list `/etc/apt/sources.list.d/docker.list`:

```text
docker-ce  docker-ce-cli  containerd.io  docker-buildx-plugin  docker-compose-plugin
```

| Check                         | Result                                 |
| ----------------------------- | -------------------------------------- |
| `docker --version`            | `Docker version 29.7.2, build a7dcaa6` |
| `docker compose version`      | `Docker Compose version v5.4.0`        |
| `systemctl is-enabled docker` | `enabled`                              |
| `systemctl is-active docker`  | `active`                               |
| `docker run --rm hello-world` | pulled and ran clean                   |

**Note on the plan's "Compose must report v2.x" check.** It reports **v5.4.0**. The intent of that check is to rule out the old Python `docker-compose` v1, which cannot parse this compose file. v5.4.0 is the Go compose-plugin lineage (the successor to v2), so the check passes — the literal string "v2" no longer appears. Not a blocker.

## Phase 3.5 — Swap (complete)

Pre-checks before writing anything: root fs is **ext4** (fallocate-safe), no existing `/swapfile`, no existing swap entry in `/etc/fstab`.

Created per the plan: 2 G `/swapfile`, mode 600, `vm.swappiness=10` in `/etc/sysctl.d/99-swap.conf`, `/swapfile none swap sw 0 0` appended to `/etc/fstab`.

```text
NAME      TYPE SIZE USED PRIO
/swapfile file   2G   0B   -2

Mem:   3.7Gi total, 522Mi used, 3.2Gi available
Swap:  2.0Gi total, 0B used
```

`systemctl daemon-reload` run afterwards; systemd now shows `swapfile.swap  loaded active active`, so it comes back on reboot via fstab. `findmnt --verify`: 0 errors, 1 warning (`non-bind mount source /swapfile is a directory or regular file`) — cosmetic, expected for all file-backed swap.

## Phase 4 — Deploy (complete)

Data tree `/srv/uos/{persistent,var-log,data,srv,var-lib-unifi,var-lib-mongodb,etc-rabbitmq-ssl}` and `/srv/uos-compose/docker-compose.yaml` created as specified, image tag substituted **literally** as `v1.6.0`. `docker compose config` validates clean.

**Ports: all 8 from the native install mapped** (GATE 0 option A), not the plan's 4:

```text
11443:443  8080:8080  3478:3478/udp  10003:10003/udp
6789:6789  8444:8444  8880:8880  8881:8881  8882:8882  5514:5514/udp
```

Pull: `ghcr.io/lemker/unifi-os-server:v1.6.0` → image `1a6a7167082d`, 2.76 GB on disk / 789 MB content. Safety check before `up`: `uosserver.service` inactive, 0 old containers, 0 conflicting port holders.

### Startup — faster than the plan predicted

Plan says 7-8 min to pull and another 7-8 to boot. Actual: pull a few minutes, **HTTP 200 within ~20 s of `up -d`**, `unifi.service` fully active at ~80 s.

| Check                                        | Result                                     |
| -------------------------------------------- | ------------------------------------------ |
| `docker compose ps`                          | `Up`, all 10 port mappings bound (v4 + v6) |
| `curl -kI https://localhost:11443`           | **`HTTP/2 200`**, `server: nginx`          |
| `systemctl is-system-running` (in container) | **`running`**                              |
| `systemctl --failed` (in container)          | **empty — zero failed units**              |

The plan warns an overall `degraded` state is normal. This deployment does **not** even reach `degraded` — it reports `running` with no failed units. Better than expected; nothing to excuse.

Service chain, all confirmed:

```text
postgresql@14-main.service      active running
mongodb.service                 active running
unifi-core.service              active running
unifi.service                   active running   (activating for ~80s first)
unifi-directory / ucs-agent / uos-agent / uos-discovery-client   active running
```

### Bind mounts confirmed (no anonymous volumes)

```text
303M  /srv/uos/var-lib-unifi
301M  /srv/uos/var-lib-mongodb
128M  /srv/uos/data
112K  /srv/uos/var-log
 24K  /srv/uos/etc-rabbitmq-ssl
 20K  /srv/uos/srv
 12K  /srv/uos/persistent
```

Data is landing on the host bind mounts as intended.

### Memory during first boot

```text
Mem:   3.7Gi total, 1.6Gi used, 2.1Gi available
Swap:  2.0Gi total, 7.7Mi used
```

Swap essentially untouched (7.7 MiB) — a fresh boot is cheap. The real test is the Phase 5 restore plus 4.2.23 → 5.1.40 schema migration; the cushion is there for it.

**GATE 4: passed.** Awaiting the human restore (Phase 5).

### Note on a polling bug (self-inflicted, corrected)

An early readiness loop used `curl … || echo "000"`, which concatenated to `000000` on failure and tripped a `!= "000"` test — it falsely reported "WEB UI RESPONDING" at 20 s. Re-run with an explicit `$?` check. The corrected result (`curl_rc=0 http=200`) is the one recorded above.

## Phase 5 — Restore (complete)

Restored from the **cloud backup** already listed in the setup wizard — same artifact as the local `.unifi` file, so no upload was needed. "Restore all applications and settings" selected.

Monitored throughout for the one real risk (OOM killer taking mongod mid-migration):

```text
18:30:58  mongo=active  unifi=active      RAM 1601M used / 2178M avail   swap 7M   oomkills=0
18:32:00  mongo=active  unifi=activating  RAM 1202M used / 2577M avail   swap 7M   oomkills=0
18:33:32  mongo=active  unifi=active      RAM 1788M used / 1991M avail   swap 8M   oomkills=0
18:34:33  mongo=active  unifi=active      RAM 1747M used / 2032M avail   swap 8M   oomkills=0
```

`unifi.service` cycled through `activating` ~18:32 → `active` ~18:33 as the restore applied. **Peak RAM 1.79 Gi of 3.7 Gi, peak swap 8 MiB, zero OOM kills.** The 4.2.23 → 5.1.40 migration was far cheaper than the plan anticipated; the swapfile was never meaningfully needed (still worth keeping).

## Phase 6 — Agent verification (pre-reboot)

| Check                                             | Result                                                                    |
| ------------------------------------------------- | ------------------------------------------------------------------------- |
| `docker compose ps`                               | `unifi-os-server \| Up 11 minutes`                                        |
| `systemctl is-system-running`                     | **`running`** (not degraded)                                              |
| `systemctl --failed`                              | **empty**                                                                 |
| mongodb / postgresql@14-main / unifi-core / unifi | all `active running`                                                      |
| `curl -kI https://localhost:11443`                | `HTTP/2 200`, nginx                                                       |
| `curl http://localhost:8080/inform`               | `400` — correct; endpoint expects a device POST, so 400 proves it listens |
| Version in container                              | `UOSSERVER.…5.1.40.…` — **5.1.40 confirmed**                              |

Bind mounts after restore (data persisted to host, no anonymous volumes):

```text
308M  /srv/uos/var-lib-unifi     (was 303M pre-restore)
301M  /srv/uos/var-lib-mongodb
130M  /srv/uos/data
144K  /srv/uos/var-log
```

Memory at rest: 1.7 Gi used, 2.0 Gi available, 8.4 MiB swap.

## Phase 6 — Human verification + reboot test (complete)

**[HUMAN] confirmed:** UI good, devices connected, inform host still unchanged (same address, port `8080`) — so no APs were orphaned.

Fresh post-migration backups taken and stored alongside the 4.x ones. Note the Network application also moved **10.2.105 → 10.5.67** as part of the restore.

| File                                | Size     |
| ----------------------------------- | -------- |
| `unifi_os_backup_<id>.unifi`        | 166752 B |
| `network_site_Default_v10.5.67.unf` | 42656 B  |

All four backups (2× pre-migration 4.x, 2× post-migration 5.x) plus the 912 MB native tarball live in `/home/aspruyt/uos-migration-backups/`.

### Reboot test — PASSED

```text
SSH back:         ~20 s
container:        auto-restarted via `restart: unless-stopped`, RestartCount=0
UI serving:       HTTP 200 immediately; unifi.service active at ~105 s
services:         mongodb / postgresql@14-main / unifi-core / unifi — all active running
system state:     running (no failed units)
inform :8080:     400 (correct — endpoint up, expects a device POST)
static IP:        unchanged on eth0 — held
swap:             /swapfile 2G active via fstab — survived
old stack:        uosserver.service disabled + inactive — did NOT reclaim ports
memory:           1.5Gi used, 2.2Gi available, 48 KiB swap
```

### Cosmetic oddity: `docker ps` reports "Up 3 months"

Not a fault. This Pi has **no RTC** (`timedatectl` → `RTC time: n/a`). It boots with a stale clock (~2026-06-05T15:35Z), Docker stamps the container's `StartedAt` during that pre-NTP window, then `systemd-timesyncd` corrects the clock forward — so the computed uptime is nonsense.

```text
StartedAt=2026-06-05T15:35:30Z   RestartCount=0
docker ps  Status="Up 3 months"  RunningFor="23 minutes ago"
```

The same artifact explains why the old `uosserver.service` reported "active since 2026-06-06; 3 months 1 day ago" while `uptime` said 19 h — see Phase 0. Trust `RunningFor` / `uptime`, not `Status`. Harmless; no action taken.

## Rollback status (still available)

The 4.2.23 install remains intact and stopped on disk. To revert:

```bash
cd /srv/uos-compose && sudo docker compose down
sudo systemctl enable --now uosserver.service
```

Keep it until the 5.1.40 stack has run clean for a while. `uosserver-purge` reclaims ~4 GB whenever that decision is made — there is no urgency at 215 G free.

## Outstanding items

1. **The native 4.2.23 install stays until roughly December 2026** — user decision, 2026-09-06. It is stopped and disabled and costs ~4 GB on a disk with 209 G free. It is the one-minute rollback path, so do not remove it early. When the time comes, `uosserver-purge` is the documented uninstaller (`uosserver` itself has no `uninstall` subcommand); its behaviour has never been verified, so probe it
   for a help/dry-run flag first.
2. **Off-box backups are handled by UniFi cloud** — automatic, weekly. The Phase 5 restore was done straight from a cloud backup listed in the setup wizard, so this path is proven, not assumed. The local copies in `/home/aspruyt/uos-migration-backups/` are a manual belt-and-braces layer, mainly for the 4.x-era artifacts that cloud will not hold once 4.2.23 is purged.
3. **The compose file lives only on the Pi**, not in git. Renovate was considered and dropped — it would open a PR but nothing on the Pi watches for merges, so it would notify without deploying. Upgrades are driven by this skill instead.
