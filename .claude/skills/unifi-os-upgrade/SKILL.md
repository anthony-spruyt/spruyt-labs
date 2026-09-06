---
name: unifi-os-upgrade
description: Upgrades, restarts, rolls back, and troubleshoots the containerised UniFi OS Server running on the Raspberry Pi (ssh alias `unifi`). Use when the user asks to "upgrade UniFi", "update UniFi OS", "bump the UOS image", mentions a lemker/unifi-os-server release tag, or asks what version the UniFi controller is on. Not for UniFi devices (APs/switches) — those update from the UniFi UI. Not for anything in the Talos cluster.
argument-hint: [target-tag]
---

# UniFi OS Server Upgrade

UniFi OS runs as a single Docker container on a Raspberry Pi 4B, **outside** the Talos cluster. Flux does not manage it. Upgrades are `compose down / pull / up -d` against a pinned image tag.

Two conventions used below:

- **[HUMAN]** marks a step this skill cannot perform itself. Stop there and ask the user to do it.
- `$` followed by a digit is an argument placeholder — substitution runs over this whole file, including code fences, so never write one inside a command.

## Quick Reference

| Item               | Value                                                       |
| ------------------ | ----------------------------------------------------------- |
| Host               | `ssh unifi` (user `aspruyt`, passwordless sudo, no browser) |
| Compose file       | `/srv/uos-compose/docker-compose.yaml` — only on the Pi     |
| Data (bind mounts) | `/srv/uos/*`                                                |
| Image              | `ghcr.io/lemker/unifi-os-server` — **always a pinned tag**  |
| Upstream repo      | `lemker/unifi-os-server`                                    |
| Web UI             | `https://<PI_IP>:11443` (self-signed)                       |
| Inform URL         | `http://<PI_IP>:8080/inform` — **never change this**        |
| Backups            | `/home/aspruyt/uos-migration-backups/` on the workstation   |

Host inventory, port and data layout, hardening, all three rollback paths, and the host's quirks are already established in `references/host-facts.md` — read it, do not re-discover any of it.

### Resolving `<PI_IP>`

This is a public repo — **no addresses are recorded here**. Everything reachable is reachable via the `ssh unifi` alias, which lives in the operator's local SSH config, so you never need a literal address to do the work. Prefer `localhost` from inside the host:

```bash
ssh unifi 'curl -kI --max-time 10 https://localhost:11443'
```

When you genuinely need the address — to hand the user a browser URL — discover it, do not ask and do not guess:

```bash
ssh unifi 'hostname -I'
```

Use it only in that turn's output. **Never write a discovered address into a repo file, commit message, issue, or PR.**

## Version Mapping (important)

The image tag and the UniFi OS version are **different numbers** and do not track each other. Never assume they match — always read the release notes to map tag → UniFi OS version, and report both.

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

## Progress checklist

Track these as todos. Phase 2 is the one omission that cannot be undone.

```text
- [ ] Phase 1 — current tag, current UniFi OS version, target tag, target UniFi OS version, release notes
- [ ] Phase 2 — fresh backup downloaded to the workstation and checksummed (HARD GATE)
- [ ] Phase 3 — tag edited on the Pi with a .bak saved, config validated, pull, down/up
- [ ] Phase 4 — verification script passes every row of the pass table
- [ ] Phase 5 — new pinned tag and resulting UniFi OS version reported
```

## Workflow

### Phase 1: Determine current and target versions

The target tag is `$0`. An unfilled placeholder is left as literal text rather than blanked, so if that still reads as a bare dollar-zero the user passed no tag — resolve the latest non-prerelease tag with the releases command above and confirm it with the user before going further.

```bash
ssh unifi 'grep image: /srv/uos-compose/docker-compose.yaml'
ssh unifi 'sudo docker exec unifi-os-server cat /usr/lib/version'
```

Report current tag, current UniFi OS version, target tag, target UniFi OS version, and the release notes between them.

### Phase 2: HARD GATE — backup first

**[HUMAN]** The backup is taken from the UniFi UI, which needs a browser. Stop and instruct the user:

> In the UniFi UI → Settings → Control Plane → Backups, take a fresh backup and download it to `/home/aspruyt/uos-migration-backups/`.

Wait for confirmation. Then verify and checksum what landed:

```bash
ls -la --time-style=+%H:%M /home/aspruyt/uos-migration-backups/
sha256sum /home/aspruyt/uos-migration-backups/*.unifi
```

**Do not proceed without a backup newer than the current controller state.** A bad release with no backup means rebuilding UniFi OS by hand.

### Phase 3: Apply

Rewrite the `image:` tag on the Pi — the compose file is not in this repo, so it cannot be edited locally. Substitute the tag **literally**, never a shell variable, and keep the `.bak` the first command writes; rollback restores it.

```bash
ssh unifi 'sudo cp /srv/uos-compose/docker-compose.yaml /srv/uos-compose/docker-compose.yaml.bak && \
  sudo sed -i "s|^\( *image: *ghcr.io/lemker/unifi-os-server:\).*|\1<TAG>|" /srv/uos-compose/docker-compose.yaml'
ssh unifi 'grep image: /srv/uos-compose/docker-compose.yaml'
```

The read-back must show the target tag before you continue.

```bash
ssh unifi 'cd /srv/uos-compose && sudo docker compose config --quiet && echo VALID'
ssh unifi 'cd /srv/uos-compose && sudo docker compose pull'      # several minutes on a Pi
ssh unifi 'cd /srv/uos-compose && sudo docker compose down && sudo docker compose up -d'
```

Never edit the compose file's `cgroup: host`, the `tmpfs` list, or the `/sys/fs/cgroup` mount. UniFi OS runs its components as systemd services inside the container and will not boot without them.

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
sudo docker exec unifi-os-server systemctl is-active mongodb postgresql@14-main unifi-core
curl -s --max-time 10 -o /dev/null -w "inform http=%{http_code}\n" http://localhost:8080/inform
sudo du -sh /srv/uos/*
free -h
EOF
```

Pass criteria:

| Check                                   | Expected                                                         |
| --------------------------------------- | ---------------------------------------------------------------- |
| `https://localhost:11443`               | `http=200`, `curl` rc `0`                                        |
| `unifi.service`                         | `active`                                                         |
| mongodb, postgresql@14-main, unifi-core | `active` for all three                                           |
| `is-system-running`                     | `running` (`degraded` is tolerable; check `--failed` if so)      |
| `http://localhost:8080/inform`          | `400` — correct, the endpoint expects a device POST              |
| `/srv/uos/*`                            | `var-lib-unifi` and `var-lib-mongodb` each in the hundreds of MB |

Single-digit MB for either of those two directories means the container is writing somewhere else and the bind mounts are wrong — stop and investigate before handing the system back.

**[HUMAN]** Ask the user to confirm in the UI: all APs/switches **Connected**, clients online, and the inform host is unchanged (same address and port `8080` as before the upgrade).

### Phase 5: Report

The compose file lives only on the Pi, so there is nothing to commit. Report the new pinned tag and the resulting UniFi OS version so both land in the transcript.

## Rollback

Restore the previous tag from the `.bak` written in Phase 3, then bring the container back up:

```bash
ssh unifi 'cd /srv/uos-compose && sudo docker compose down'
ssh unifi 'sudo cp /srv/uos-compose/docker-compose.yaml.bak /srv/uos-compose/docker-compose.yaml'
ssh unifi 'cd /srv/uos-compose && sudo docker compose up -d'
```

Bind-mounted data in `/srv/uos/` survives `compose down` — only the container is replaced. If the new version migrated the database schema forward, a downgrade needs the Phase 2 backup restored through the setup wizard. All three rollback paths, including the legacy native fallback, are in the reference.

## Gotchas

- **Never change `UOS_SYSTEM_IP` in the compose file.** It is already set correctly on the host and must match the address every AP has been told to inform to. Changing it orphans every device on the site. A tag bump touches the `image:` line and nothing else.
- **Never run both stacks at once.** The legacy native install and the container bind the same ports. Confirm `systemctl is-active uosserver.service` is `inactive` before any `compose up`.
- **The Pi has no RTC.** It boots with a stale clock, so `docker ps` reports nonsense uptimes like "Up 3 months" for a container started minutes ago. Trust `RunningFor` and `uptime`, not `Status`.
- **Do not add Watchtower or any unattended auto-updater.** Unattended pulls on a network controller are how you discover a bad release at 3am.
- Application updates (Network, InnerSpace, Protect) are **separate** from the container image and are applied from the UI: Settings → Control Plane → Updates.

## Old patterns

<details>
<summary>Native (pre-container) install as a last-resort fallback</summary>

Before the migration, UniFi OS ran natively under rootless podman. That install may still be on disk, stopped and disabled. Check before assuming:

```bash
ssh unifi 'systemctl is-enabled uosserver.service; ls -la /usr/local/bin/uosserver'
```

If present, it is a last-resort fallback only. It requires `compose down` first because both stacks bind the same ports, and its podman runs rootless as user `uosserver`, so `sudo podman ps` as root shows nothing. Full procedure is in the reference.

</details>

## Additional Resources

- [`${CLAUDE_SKILL_DIR}/references/host-facts.md`](references/host-facts.md) — host inventory, ports, data layout, rollback paths, hardening, and the host's quirks.
