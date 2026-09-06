---
name: unifi-os-upgrade
description: Upgrade the containerised UniFi OS Server running on the Raspberry Pi (ssh alias `unifi`). Use when the user asks to "upgrade UniFi", "update UniFi OS", "bump the UOS image", mentions a lemker/unifi-os-server release tag, or asks what version the UniFi controller is on. Also covers restarting, rolling back, and troubleshooting that container. Not for UniFi devices (APs/switches) — those update from the UniFi UI. Not for anything in the Talos cluster.
argument-hint: [target-tag]
---

# UniFi OS Server Upgrade

The UniFi controller runs as a single Docker container on a Raspberry Pi 4B, **outside** the Talos cluster. Flux does not manage it. Upgrades are `compose down / pull / up -d` against a pinned image tag.

## Quick Reference

| Item               | Value                                                       |
| ------------------ | ----------------------------------------------------------- |
| Host               | `ssh unifi` (user `aspruyt`, passwordless sudo, no browser) |
| Compose dir        | `/srv/uos-compose/docker-compose.yaml`                      |
| Data (bind mounts) | `/srv/uos/*`                                                |
| Image              | `ghcr.io/lemker/unifi-os-server` — **always a pinned tag**  |
| Upstream repo      | `lemker/unifi-os-server`                                    |
| Web UI             | `https://<PI_IP>:11443` (self-signed)                       |
| Inform URL         | `http://<PI_IP>:8080/inform` — **never change this**        |
| Backups            | `/home/aspruyt/uos-migration-backups/` on the workstation   |
| Migration record   | `references/host-facts.md`                                  |

Read `references/host-facts.md` for the full host inventory, the original migration log, and the still-present 4.2.23 fallback install. Do not re-discover any of it.

### Resolving `<PI_IP>`

This is a public repo — **no addresses are recorded here**. Everything reachable is reachable via the `ssh unifi` alias, which lives in the operator's local SSH config, so you never need a literal address to do the work. Prefer `localhost` from inside the host:

```bash
ssh unifi 'curl -kI --max-time 10 https://localhost:11443'
```

When you genuinely need the address — to hand the user a browser URL — discover it, do not ask and do not guess:

```bash
ssh unifi 'ip -4 -o addr show scope global | awk "{print \$2, \$4}"'
```

Use it only in that turn's output. **Never write a discovered address into a repo file, commit message, issue, or PR.**

## Version Mapping (important)

The image tag and the UniFi OS version are **different numbers**. Tag `v1.6.0` ships UOS `5.1.40`. Never assume they match — always read the release notes to map tag → UOS version.

```bash
curl -s "https://api.github.com/repos/lemker/unifi-os-server/releases?per_page=10" |
  python3 -c "import json,sys; [print(r['tag_name'], r['prerelease'], r['published_at']) for r in json.load(sys.stdin)]"
```

Pick the latest release with `prerelease=False`. **Never** use `latest` or any `-ea` tag.

Confirm the tag has an arm64 build before pulling:

```bash
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:lemker/unifi-os-server:pull&service=ghcr.io" |
  python3 -c "import sys,json;print(json.load(sys.stdin)['token'])")
curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  "https://ghcr.io/v2/lemker/unifi-os-server/manifests/<TAG>" |
  python3 -c "import sys,json; [print(m['platform']) for m in json.load(sys.stdin).get('manifests',[])]"
```

## Workflow

### Phase 1: Determine current and target versions

```bash
ssh unifi 'grep image: /srv/uos-compose/docker-compose.yaml'
ssh unifi 'sudo docker exec unifi-os-server cat /usr/lib/version'
```

Report current tag, current UOS version, target tag, target UOS version, and the release notes between them.

### Phase 2: HARD GATE — backup first

**[HUMAN]** You have no browser. Stop and instruct the user:

> In the UniFi UI → Settings → Control Plane → Backups, take a fresh backup and download it to `/home/aspruyt/uos-migration-backups/`.

Wait for confirmation. Then verify and checksum what landed:

```bash
ls -la --time-style=+%H:%M /home/aspruyt/uos-migration-backups/
sha256sum /home/aspruyt/uos-migration-backups/*.unifi
```

**Do not proceed without a backup newer than the current controller state.** A bad release with no backup means rebuilding the controller by hand.

### Phase 3: Apply

Edit the `image:` tag in `/srv/uos-compose/docker-compose.yaml` to the target — substitute the tag **literally**, never a shell variable. Then:

```bash
ssh unifi 'cd /srv/uos-compose && sudo docker compose config --quiet && echo VALID'
ssh unifi 'cd /srv/uos-compose && sudo docker compose pull'      # several minutes on a Pi
ssh unifi 'cd /srv/uos-compose && sudo docker compose down && sudo docker compose up -d'
```

Never edit the compose file's `cgroup: host`, the `tmpfs` list, or the `/sys/fs/cgroup` mount. UOS runs its components as systemd services inside the container and will not boot without them.

### Phase 4: Verify

Poll until `unifi.service` is `active` — expect ~2 min. **Check `curl`'s exit code, not just the body:** a failed `curl` with an `|| echo` fallback can produce a string that passes a naive test.

```bash
ssh unifi 'bash -s' <<'EOF'
for i in $(seq 1 30); do
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 https://localhost:11443); rc=$?
  u=$(sudo docker exec unifi-os-server systemctl is-active unifi.service 2>/dev/null)
  echo "[$((i*15))s] rc=$rc http=$code unifi=$u"
  [ "$rc" = "0" ] && [ "$code" = "200" ] && [ "$u" = "active" ] && { echo "UP"; break; }
  sleep 15
done
sudo docker exec unifi-os-server systemctl is-system-running
sudo docker exec unifi-os-server systemctl --failed --no-pager --no-legend
curl -s --max-time 10 -o /dev/null -w "inform http=%{http_code}\n" http://localhost:8080/inform
sudo du -sh /srv/uos/*
free -h
EOF
```

Pass criteria:

| Check                                   | Expected                                                       |
| --------------------------------------- | -------------------------------------------------------------- |
| `https://localhost:11443`               | `http=200`, `curl` rc `0`                                      |
| `unifi.service`                         | `active`                                                       |
| mongodb, postgresql@14-main, unifi-core | `active running`                                               |
| `is-system-running`                     | `running` (`degraded` is tolerable; check `--failed` if so)    |
| `http://localhost:8080/inform`          | `400` — correct, the endpoint expects a device POST            |
| `/srv/uos/*`                            | non-trivial sizes — data on bind mounts, not anonymous volumes |

**[HUMAN]** Ask the user to confirm in the UI: all APs/switches **Connected**, clients online, and the inform host is unchanged (same address and port `8080` as before the upgrade).

### Phase 5: Commit

The compose file lives only on the Pi. If it has been mirrored into this repo, commit the tag bump with `Ref #<issue>`. Otherwise just report the new pinned tag so it is in the transcript.

## Rollback

```bash
ssh unifi 'cd /srv/uos-compose && sudo docker compose down'
# restore the previous tag in docker-compose.yaml, then:
ssh unifi 'cd /srv/uos-compose && sudo docker compose up -d'
```

Bind-mounted data in `/srv/uos/` survives `compose down` — only the container is replaced. If the new version migrated the database schema forward, a downgrade needs the Phase 2 backup restored through the setup wizard.

The original native 4.2.23 install may still be on disk, stopped and disabled. Check before assuming:

```bash
ssh unifi 'systemctl is-enabled uosserver.service; ls -la /usr/local/bin/uosserver'
```

If present, that is a last-resort fallback — see `references/host-facts.md`. It requires `compose down` first because both stacks bind the same ports.

## Gotchas

- **Never change `UOS_SYSTEM_IP` in the compose file.** It is already set correctly on the host and must match the address every AP has been told to inform to. Changing it orphans every device on the site. A tag bump touches the `image:` line and nothing else.
- **Never run both stacks at once.** The old podman-based install and the Docker container bind the same ports. Confirm `systemctl is-active uosserver.service` is `inactive` before any `compose up`.
- **Stopping the old stack takes two commands.** `systemctl stop uosserver.service` only stops the supervisor; the rootless podman container keeps running and keeps the ports. Also run `sudo /usr/local/bin/uosserver stop`.
- **The Pi has no RTC.** It boots with a stale clock, so `docker ps` reports nonsense uptimes like "Up 3 months" for a container started minutes ago. Trust `RunningFor` and `uptime`, not `Status`.
- **The old install's podman runs rootless as user `uosserver`.** `sudo podman ps` as root shows nothing. Use `sudo -u uosserver env HOME=/home/uosserver XDG_RUNTIME_DIR=/run/user/1001 podman ps -a`.
- **Do not run `stat -fc %T /sys/fs/cgroup/`** — it prints `UNKNOWN (0x63677270)` on this host, which IS `CGROUP2_SUPER_MAGIC` and is a pass. Test `/sys/fs/cgroup/cgroup.controllers` exists instead.
- **This is Ubuntu, not Raspberry Pi OS.** No `dphys-swapfile`. Use Docker's Ubuntu repo.
- **Do not add Watchtower or any unattended auto-updater.** Unattended pulls on a network controller are how you discover a bad release at 3am.
- Application updates (Network, InnerSpace, Protect) are **separate** from the container image and are applied from the UI: Settings → Control Plane → Updates.

## Additional Resources

- [references/host-facts.md](references/host-facts.md) — host inventory, migration record, backup locations, and the fallback install's exact state.
