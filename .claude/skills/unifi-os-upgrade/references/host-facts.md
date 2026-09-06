# UniFi OS Server — host facts

Reference for the `unifi-os-upgrade` skill. Host: `ssh unifi`. Treat this as established — do not re-discover it.

**No addresses are recorded here.** This is a public repo. Reach the host via the `ssh unifi` alias and prefer `localhost` from inside it; discover an address at runtime only when you need to hand the user a browser URL.

## Contents

- [Host](#host)
- [Data layout](#data-layout)
- [Ports](#ports)
- [Expected startup](#expected-startup)
- [Backups](#backups)
- [Rollback](#rollback)
- [Host hardening](#host-hardening)
- [Gotchas](#gotchas)
- [Old patterns](#old-patterns)

## Host

| Item             | Value                                                                           |
| ---------------- | ------------------------------------------------------------------------------- |
| Hardware         | Raspberry Pi 4B, arm64                                                          |
| OS               | Ubuntu LTS — keep it on LTS, never let it drift onto an interim release         |
| Kernel           | `raspi` flavour on A/B boot slots — `ssh unifi 'uname -r'`                      |
| Disk             | USB SSD, separate small `/boot/firmware` — `ssh unifi 'df -h / /boot/firmware'` |
| Swap             | `/swapfile` via `/etc/fstab`, `vm.swappiness=10`                                |
| Docker / Compose | from Docker's Ubuntu repo — `ssh unifi 'sudo docker compose version'`           |
| UniFi OS         | current tag and version are read in the skill's Phase 1 — not recorded here     |
| Compose file     | `/srv/uos-compose/docker-compose.yaml` — **only on the Pi, not in git**         |
| Data             | bind mounts under `/srv/uos/`                                                   |

An interim release is how this host ended up unpatched before, with `unattended-upgrades` reporting zero pending updates because none were being published.

### Data layout

```text
/srv/uos/var-lib-unifi
/srv/uos/var-lib-mongodb
/srv/uos/data
/srv/uos/var-log
/srv/uos/etc-rabbitmq-ssl
/srv/uos/srv
/srv/uos/persistent
```

Bind mounts, not anonymous volumes — data survives `compose down`. `var-lib-unifi` and `var-lib-mongodb` should each be in the hundreds of MB; single-digit MB after an upgrade means the container is writing somewhere else and the mounts are wrong.

### Ports (all 10 published)

```text
11443:443  8080:8080  3478:3478/udp  10003:10003/udp  5514:5514/udp
6789:6789  8444:8444  8880:8880  8881:8881  8882:8882
```

`11443` is the web UI, `8080` is device inform, the rest are speedtest / hotspot / STUN / syslog. Host `443` is deliberately unused.

### Expected startup

HTTP 200 on `11443` within ~20-60 s of `up -d`; `unifi.service` reaches `active` at ~80-150 s. `is-system-running` should report `running` with zero failed units — this host does not normally reach even `degraded`.

## Backups

- **UniFi cloud, weekly, automatic.** The primary off-box copy, and a proven restore path — a cloud backup listed in the setup wizard was used to rebuild the container after the migration.
- **Workstation:** `/home/aspruyt/uos-migration-backups/` — manual `.unifi` backups plus a tarball of the pre-migration podman volumes.
- The `.unifi` file is the full UniFi OS backup and **contains the Network application data**. The `.unf` site export is not a separate Network backup — Network 10.x folded that download into the UniFi OS backup. There is nothing else to obtain from the UI.

Never keep the only copy of a backup on the Pi — it is the disk the backup protects against.

## Rollback

### 1. Previous image tag (normal case)

```bash
ssh unifi 'cd /srv/uos-compose && sudo docker compose down'
ssh unifi 'sudo cp /srv/uos-compose/docker-compose.yaml.bak /srv/uos-compose/docker-compose.yaml'
ssh unifi 'cd /srv/uos-compose && sudo docker compose up -d'
```

If no `.bak` exists, rewrite the `image:` tag with the same `sed` the skill uses in Phase 3, substituting the previous tag literally.

Bind-mounted data survives `compose down`. If the new version migrated the database schema forward, a downgrade needs a backup restored through the setup wizard.

### 2. Kernel (automatic)

Boot uses `flash-kernel-piboot` A/B slots, selected by `os_prefix` in `/boot/firmware/config.txt`:

```text
[all]     os_prefix=current/    # known-good, state=good
[tryboot] os_prefix=new/        # candidate,  state=unknown
```

`piboot-try-reboot.service` tryboots into the candidate at `sysinit.target`; `piboot-try-validate.service` promotes it before `getty.target`. **A candidate that fails to boot falls back to `current/` on the next power cycle by itself** — no console needed. After promotion `new/` is gone and `current/state` reads `good`. Never hand-edit those directories.

### 3. Native install (last resort)

See [Old patterns](#old-patterns).

## Host hardening

| Setting    | State                                                                                         |
| ---------- | --------------------------------------------------------------------------------------------- |
| SSH        | key-only — `/etc/ssh/sshd_config.d/10-hardening.conf`, `PermitRootLogin no`, `MaxAuthTries 3` |
| `fail2ban` | `sshd` jail, systemd backend, `bantime 1h`, `maxretry 5`                                      |
| `ufw`      | active, default deny incoming, `limit` on 22/tcp, explicit allows for all 10 UniFi ports      |
| Container  | not privileged, `docker-default` AppArmor, only `CAP_NET_ADMIN` + `CAP_NET_RAW`               |

`fail2ban`'s `ignoreip` allowlists the admin workstation subnet and both Docker bridges, so a fumbled key cannot lock anyone out of a headless box. Never re-enable `PasswordAuthentication`.

A newly published port needs a matching rule or it will answer on `localhost` and fail from the network:

```bash
ssh unifi 'sudo ufw allow <PORT>/<PROTO> comment "unifi-os"'
```

Caveat: `ufw` does **not** actually filter Docker-published ports — Docker's iptables rules are evaluated first. Those rules document intent and protect host services such as SSH. To restrict the UniFi ports by source, add `DOCKER-USER` rules, which requires knowing the VLAN layout of the AP subnets.

## Gotchas

- **The Pi has no RTC.** It boots with a stale clock, so `docker ps` and `systemctl status` report nonsense ages like "Up 3 months" for something started minutes ago. Trust `RunningFor` and `uptime`, not `Status`.
- **`sshd -t` fails with "Missing privilege separation directory: /run/sshd"** when `ssh.service` is inactive. SSH is socket-activated, so `/run/sshd` only exists per-connection. `sudo mkdir -p /run/sshd` first, then it passes. Confirm with a real `-o ControlPath=none` login — a reused multiplexed connection will happily "succeed" without authenticating and tell you nothing.
- **arm64 lives on `archive.ubuntu.com`, not `ports.ubuntu.com`.** Do not "fix" the sources.
- **`do-release-upgrade` prints "Your Ubuntu release is not supported anymore" and then offers the upgrade anyway.** The message is emitted before the `new_dist` check; the exit code is 0. Read the whole output.
- **`flash-kernel` names a Pi 5 DTB (`bcm2712-rpi-5-b.dtb`) on this Pi 4.** It stages every Pi DTB and the firmware selects by hardware at boot. Confirm `bcm2711-rpi-4-b.dtb` exists in the slot and move on.
- **Do not run `stat -fc %T /sys/fs/cgroup/`** — it prints `UNKNOWN (0x63677270)` here, which IS `CGROUP2_SUPER_MAGIC` and is a pass. Test that `/sys/fs/cgroup/cgroup.controllers` exists instead.
- **This is Ubuntu, not Raspberry Pi OS.** No `dphys-swapfile`. Use Docker's Ubuntu repo.
- **Compose reports a v5.x version, not v2.x.** That is the Go compose-plugin lineage, the successor to v2 — not the old Python `docker-compose` v1. Any check looking for the literal string "v2" is stale.

## Old patterns

<details>
<summary>Native (pre-container) install as a last-resort rollback</summary>

The original podman install may still be on disk, **stopped and disabled**. Verify it is there before assuming:

```bash
ssh unifi 'systemctl is-enabled uosserver.service; ls -la /usr/local/bin/uosserver'
```

Bringing it back:

```bash
ssh unifi 'cd /srv/uos-compose && sudo docker compose down'   # required — both stacks bind the same ports
ssh unifi 'sudo systemctl enable --now uosserver.service'
```

Its podman runs **rootless as user `uosserver`** (uid 1001) — `sudo podman ps` as root shows nothing:

```bash
sudo -u uosserver env HOME=/home/uosserver XDG_RUNTIME_DIR=/run/user/1001 podman ps -a
```

Stopping it takes **two** commands; `systemctl stop` alone leaves the container running and holding the ports:

```bash
sudo systemctl stop uosserver.service
sudo /usr/local/bin/uosserver stop
```

The uninstaller is `/usr/local/bin/uosserver-purge` (`uosserver` itself has no `uninstall` subcommand). Its behaviour has **never been verified** — probe it for a help/dry-run flag first. It reclaims several GB.

</details>
