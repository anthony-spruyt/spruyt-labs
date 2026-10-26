# Enshrouded Live Map

A live world map for the Enshrouded server at `https://enshrouded-map.${EXTERNAL_DOMAIN}`, using [oggii/enshrouded-livemap](https://github.com/oggii/enshrouded-livemap) v1.7.0 (MIT). It shows online players, deaths, Flame Altars, fog and discovered places, weather and time, creatures, and ore and chest finds.

## How the mod works

The release zip holds `iphlpapi.dll` and a `livemap/` folder (web page, tiles, icons, about 10 MB). The DLL goes next to `enshrouded_server.exe`. The game loads it instead of the system `iphlpapi.dll`, and it forwards every real call to the system one. It reads game state from memory and runs a small HTTP/1.1 server inside the game process (`src/web.cpp`): static files from `livemap/`, JSON endpoints and a server-sent events stream at `/events`. Every request needs `?key=<Key>` from the `[livemap]` section of `livemap.ini`. The DLL writes that file only when it is missing and never rewrites it (`src/config.cpp`). It saves its history (`deaths.json`, `finds.json`, `explored.json`, `discovered.json`, `objects.json`) in `livemap/`.

On Wine the game only loads the native DLL with `WINEDLLOVERRIDES=iphlpapi=n,b`.

## Current setup

- `cluster/apps/enshrouded/enshrouded/app/values.yaml`: app-template 5.3.0 StatefulSet on `mornedhels/enshrouded-server:1.8.1-wine`. Server files live in `/opt/enshrouded/server` on the `enshrouded-game` PVC (re-downloadable, not backed up). Saves live on `enshrouded-saves` at `/opt/enshrouded-saves` (Velero backs it up).
- One Service, `game`: a LoadBalancer on UDP 15637 with a pinned LB IP and the `enshrouded.${EXTERNAL_DOMAIN}` external-dns name. With one Service, app-template names it after the release: `enshrouded`.
- `app/network-policies.yaml`: UDP 15637 in from `world`, internet egress on any port (Steam needs it), LAN UDP egress.
- No Traefik route and no Cloudflare Tunnel route for Enshrouded.
- Cloudflare custom rules apply to every tunnel host, the new one included: outside Australia is blocked, bots are blocked, cloud networks get a managed challenge (`infra/terraform/cloudflare/rulesets.tf`).
- The image runs `BOOTSTRAP_HOOK` (`eval`) as the `enshrouded` user after Wine boots and before `enshrouded-updater` starts. Only the updater starts the server, so the hook must finish first. supervisord passes the container env to the hook and to `wine enshrouded_server.exe`. The image never sets `WINEDLLOVERRIDES` itself.
- The image has `curl`, `python3` and `zip`, but no `unzip`.

## Target

### 1. Install hook: `cluster/apps/enshrouded/enshrouded/app/livemap-install.sh`

A shell script in its own ConfigMap, `enshrouded-livemap-script`. Add it to the existing `configMapGenerator` in `app/kustomization.yaml` with a per-generator `options: {disableNameSuffixHash: true}`. Don't use the global `generatorOptions`: that would also strip the hash from `enshrouded-values`, and values changes would stop rolling the HelmRelease. The values reference the script ConfigMap by name, so it can't carry a hash. Reloader restarts the pod when it changes.

The script uses `root=/opt/enshrouded/server`, or `$LIVEMAP_ROOT` when that is set, so the gates can run it against a temp dir. It does this, in order:

1. Skip to step 4 only if all three hold: `$root/livemap/.installed` holds `$LIVEMAP_SHA256`, `$root/iphlpapi.dll` exists, and `$root/livemap/index.html` exists. The marker sits on the saves PVC and the DLL on the game PVC, so a rebuilt game PVC must trigger a reinstall.
2. Download `https://github.com/oggii/enshrouded-livemap/releases/download/$LIVEMAP_VERSION/EnshroudedLiveMap-<version without v>.zip` into a new temp dir with `curl -fsSL --connect-timeout 10 --max-time 120 --retry 2`. Check it against `$LIVEMAP_SHA256` with `sha256sum -c`. If the download or the check fails, log one line and go to step 4. The files from the last good install stay in place.
3. Extract with `python3 -I -m zipfile -e` into the temp dir. Copy `iphlpapi.dll` to `$root/`. Copy the contents of `livemap/` over `$root/livemap/` without deleting anything already there, so the history JSON files survive. Shipped files, `maps.json` included, are replaced on every version bump. Write the sha to `.installed`. Remove the temp dir.
4. Write `$root/livemap.ini` from scratch on every start. Line 1 is `[livemap]`, because the DLL reads every key from that section. Without the header it falls back to defaults, an empty key, and a 403 on every request. Then:
   - `Enabled=1`, `Port=15637`, `Bind=0.0.0.0`
   - `PublicUrl=$LIVEMAP_PUBLIC_URL`, `DetectPublicAddress=0`, `AnnounceInChat=1`
   - `UpdateMs=250`, `Log=1`, `LogDiagnostics=0`
   - `Key=`: the `Key` from the `[livemap]` section of the existing `livemap.ini`, if it has one. Otherwise 16 characters from `/dev/urandom` (alphabet `abcdefghjkmnpqrstuvwxyz23456789`). The script never prints the key.
5. If `$root/livemap.log` is over 10 MB, keep only its last 1000 lines.
6. Always exit 0, so a map problem can never stop the game server from starting.

Flux substitutes `${...}` in every rendered manifest, so the script must not contain `${`. Use `$var` only, and get the version without the `v` with `sed`.

### 2. `cluster/apps/enshrouded/enshrouded/app/values.yaml`

- Env:
  - `WINEDLLOVERRIDES: "iphlpapi=n,b"`
  - `BOOTSTRAP_HOOK: "timeout 300 bash /opt/livemap/livemap-install.sh || true"`. The cap matters because the hook blocks the server start (see Current setup).
  - `LIVEMAP_PUBLIC_URL: https://enshrouded-map.${EXTERNAL_DOMAIN}`
  - The version and hash pair. The shared "Annotated YAML release tag with asset sha256" Renovate manager in repo-operator `annotated.json5` bumps both together:

    ```yaml
    # renovate: depName=oggii/enshrouded-livemap datasource=github-release-attachments digest=sha256
    LIVEMAP_VERSION: "v1.7.0"
    LIVEMAP_SHA256: "edb1c346b3d245307239de8b2561713c04d2b49170011b98f3e718c760d325b9"
    ```

- Container port `map`: 15637/TCP.
- Services:
  - `game` gets `forceRename: enshrouded`. Once there are two Services, app-template appends the identifier to every Service name (`_determineResourceNameFromValues.tpl` in the bjw-s common library). Without the pin, the LoadBalancer would be renamed `enshrouded-game` and recreated.
  - New `map`: ClusterIP, TCP 15637, controller `enshrouded`. It renders as `enshrouded-map`. The `game` LoadBalancer stays UDP only.
- Persistence:
  - A `livemap-script` ConfigMap mount of `enshrouded-livemap-script` at `/opt/livemap` (mode 0755, read-only).
  - `saves` gets a second `advancedMounts` entry: `subPath: livemap` at `/opt/enshrouded/server/livemap`. That puts the map history on the backed-up PVC. The image's hourly backup zips only `world*.ksd`, so this does not grow the save zips. The entrypoint's recursive chown of `/opt/enshrouded` and of `SERVER_SAVE_DIR` covers the new folder.

### 3. `cluster/apps/enshrouded/enshrouded/app/network-policies.yaml`

Add `allow-traefik-livemap-ingress`: TCP 15637 from `k8s:io.kubernetes.pod.namespace: traefik`, `k8s:app.kubernetes.io/name: traefik`. Copy the Foundry `allow-traefik-ingress` shape.

### 4. Traefik: `cluster/apps/traefik/traefik/ingress/enshrouded/`

Copy `ingress/foundryvtt/`, minus its middlewares:

- `certificates.yaml`: Certificate `enshrouded-map-${EXTERNAL_DOMAIN/./-}` in namespace `enshrouded`, secret `enshrouded-map-${EXTERNAL_DOMAIN/./-}-tls`, for `enshrouded-map.${EXTERNAL_DOMAIN}`.
- `ingress-routes.yaml`: IngressRoute `ingress-routes-wan-https` in namespace `enshrouded` on `websecure`, for `` Host(`enshrouded-map.${EXTERNAL_DOMAIN}`) ``. It targets Service `enshrouded-map`, namespace `enshrouded`, port 15637, with `passHostHeader: true`. It carries the cert-manager, external-dns hostname and `${TRAEFIK_IP4}` target annotations, so LAN clients go straight to Traefik. No `compress` middleware: the DLL sends pre-gzipped data files itself, and `/events` is a stream.
- `kustomization.yaml` listing the two files.
- Add `./enshrouded` to `cluster/apps/traefik/traefik/ingress/kustomization.yaml`, between `coder-system` and `flux-system`.
- Add `enshrouded` to the `traefik-ingress` `dependsOn` in `cluster/apps/traefik/traefik/ks.yaml`, as `.claude/rules/ingress-and-certificates.md` requires. This ties ingress reconciles to the game server's Kustomization being Ready, as `crafty-controller` and `foundryvtt` already do.

### 5. Cloudflare: `infra/terraform/cloudflare/tunnel.tf`

Add a `tunnel_routes` entry between `code` and `flux-webhook`:

```hcl
{
  subdomain      = "enshrouded-map"
  service        = local.traefik_service
  origin_request = { http2_origin = true, origin_server_name = "enshrouded-map.${var.zone_name}" }
},
```

This adds the tunnel ingress rule and the proxied CNAME. The owner confirms the Terraform Cloud run.

### 6. `cluster/apps/enshrouded/enshrouded/README.md`

- Fix "no web UI or HTTP endpoint" in the Overview.
- Add a "Live map" section:
  - What the map is, its URL, and that players get the link (with the key) in game chat when they join.
  - The hook and where files live: the DLL and `livemap.ini` on the game PVC, `livemap/` on the saves PVC.
  - How bumps work: Renovate moves version and hash together, and a bad hash keeps the last good version. Shipped files in `livemap/` are replaced on each bump, so don't hand-edit them.
  - How to change the key: delete the `Key=` line from `livemap.ini`, then restart the pod. Rebuilding the game PVC also makes a new key, and the old links stop working.
  - The map serves at most 32 open pages at once.
  - Only visitors in Australia can open it from outside the LAN.
  - Rollback: revert the commit. A failed rollout only self-remediates after the 70m HelmRelease timeout, so don't wait for it.

## Order

1. One commit with sections 1 to 4 and 6, plus the Terraform route (5). Deploy when nobody is online: the first rollout may restart the pod twice (Helm and Reloader). Flux applies the cluster side. The route stays dark until the Terraform run is applied.
2. The owner confirms the Cloudflare Terraform Cloud run.
3. Check the map (gates below).

## Riskiest assumption

That the DLL loads under this image's Wine, finds what it needs in the current game build, and leaves the server healthy, LAN direct connections included.

Proof after deploy:

- `livemap.log` shows the `livemap 1.7.0 starting` line with `real iphlpapi loaded` (not `MISSING`), then `web map listening on 0.0.0.0:15637 (TCP)`. The hook logged no failure.
- In the pod, with the key read from `livemap.ini` into a shell variable, print only status codes, never the key:
  - `curl` to `http://127.0.0.1:15637/state?key=...` returns 200.
  - `curl --doh-url https://cloudflare-dns.com/dns-query` to `https://enshrouded-map.${EXTERNAL_DOMAIN}/state?key=...` returns 200. DoH makes the name resolve to Cloudflare, so the request takes the tunnel path; the cluster's own DNS may point it straight at Traefik. A cloud runner can't stand in for this: the WAF challenges cloud networks.
  - The same URL without the key returns the DLL's 403 body ("Open the map with ?key=").
  - `curl --http1.1 -N` to `/events?key=...` on the public URL stays open for over 60 s and keeps receiving data.
- `supervisorctl restart enshrouded-server` in the pod, then `livemap.log` shows `listening` again.
- The server is RUNNING and still listed in the in-game server browser. A LAN player joins directly, not relayed. Tick time in the Enshrouded Grafana dashboard (vlogs `[ecss] Stats:` recording rules) shows no change against the hour before.

Rollback: revert the commit. Removing `WINEDLLOVERRIDES` alone also works: Wine then loads its builtin `iphlpapi`, and the DLL on disk does nothing.

## Gates for the builder

- Render the enshrouded and traefik Kustomizations with the cluster variables substituted:
  - The script in `enshrouded-livemap-script` matches the file byte for byte.
  - `enshrouded-values` still has its hash suffix, and `enshrouded-livemap-script` has none.
- `helm template` app-template 5.3.0 with the old and new values. The only Service names are `enshrouded` (the LoadBalancer, unchanged) and `enshrouded-map`, and no other object changes name.
- `shellcheck` passes on the script.
- Run the script with `LIVEMAP_ROOT` set to a temp dir, downloading the real release. Show each of these:
  - A fresh run installs the DLL and `livemap/` and writes an ini that `python3 -I` `configparser` reads as section `livemap` with every key above and a 16-character key from the alphabet.
  - A second run keeps the same key and skips the download.
  - Deleting `iphlpapi.dll` forces a reinstall.
  - A wrong `LIVEMAP_SHA256` keeps the old files and exits 0.
  - A `LIVEMAP_VERSION` with no release (a 404) keeps the old files and exits 0.
  - No output contains the key.
- `terraform fmt -check` and `terraform validate` pass in `infra/terraform/cloudflare`.

## Out of scope

Gameplay mods through a mod loader such as ShroudForge get their own issue. They would add `dbghelp` and `winmm` to `WINEDLLOVERRIDES`, next to `iphlpapi`, with no clash.
