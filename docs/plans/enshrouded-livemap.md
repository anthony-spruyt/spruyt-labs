# Enshrouded Live Map

A live world map for the Enshrouded server at `https://enshrouded-map.${EXTERNAL_DOMAIN}`, using [oggii/enshrouded-livemap](https://github.com/oggii/enshrouded-livemap) v1.7.0 (MIT). It shows online players, deaths, Flame Altars, fog and discovered places, weather and time, creatures, and ore and chest finds.

## How the mod works

The release zip holds `iphlpapi.dll` and a `livemap/` folder (web page, tiles, icons, about 10 MB). The DLL goes next to `enshrouded_server.exe`. The game loads it instead of the system `iphlpapi.dll`, and it forwards every real call to the system one. It reads game state from memory and runs a small HTTP server inside the game process (`src/web.cpp`): static files from `livemap/`, JSON endpoints and a server-sent events stream at `/events`. Every request needs `?key=<Key>` from `livemap.ini`. The DLL also saves its history (`deaths.json`, `finds.json`, `explored.json`, `discovered.json`, `objects.json`) in `livemap/`.

On Wine the game only loads the native DLL with `WINEDLLOVERRIDES=iphlpapi=n,b`.

## Current setup

- `cluster/apps/enshrouded/enshrouded/app/values.yaml`: bjw-s app-template StatefulSet on `mornedhels/enshrouded-server:1.8.1-wine`. Server files live in `/opt/enshrouded/server` on the `enshrouded-game` PVC (re-downloadable, not backed up). Saves live on `enshrouded-saves` at `/opt/enshrouded-saves` (Velero backs it up).
- One Service, `game`: a LoadBalancer on UDP 15637 with the `enshrouded.${EXTERNAL_DOMAIN}` external-dns name. Cloudflare holds a DNS-only A record for that name (`infra/terraform/cloudflare/dns.tf`).
- `app/network-policies.yaml`: UDP 15637 in from `world`, internet egress on any port (Steam needs it), LAN UDP egress.
- No Traefik route and no Cloudflare Tunnel route for Enshrouded.
- Cloudflare custom rules apply to every tunnel host, the new one included: outside Australia is blocked, bots are blocked, cloud networks get a managed challenge (`infra/terraform/cloudflare/rulesets.tf`).
- The image runs `BOOTSTRAP_HOOK` (`eval`) as the `enshrouded` user after Wine boots and before the updater starts the server. supervisord passes the container env to the hook and to `wine enshrouded_server.exe`.
- The image has `curl`, `python3` and `zip`, but no `unzip`.

## Target

### 1. Install hook: `cluster/apps/enshrouded/enshrouded/app/livemap-install.sh`

A shell script in a ConfigMap (`configMapGenerator` with `options.disableNameSuffixHash: true`, as in `cluster/apps/claude-agents-shared/base/kustomization.yaml`). It is mounted read-only into the app container and run by `BOOTSTRAP_HOOK: bash /opt/livemap/livemap-install.sh`. Reloader already restarts the pod when the ConfigMap changes.

It does this, in order:

1. If `/opt/enshrouded/server/livemap/.installed` already holds `$LIVEMAP_SHA256`, skip to step 4.
2. Download `https://github.com/oggii/enshrouded-livemap/releases/download/$LIVEMAP_VERSION/EnshroudedLiveMap-<version without v>.zip` into a new temp dir. Check it against `$LIVEMAP_SHA256` with `sha256sum -c`. If the download or the check fails, log one line and go to step 4. The files from the last good install stay in place.
3. Extract with `python3 -I -m zipfile -e` into the temp dir. Copy `iphlpapi.dll` to `/opt/enshrouded/server/`. Copy the contents of `livemap/` over `/opt/enshrouded/server/livemap/` without deleting anything already there, so the history JSON files survive. Write the sha to `.installed`. Remove the temp dir.
4. Write `/opt/enshrouded/server/livemap.ini` from scratch on every start:
   - `Enabled=1`, `Port=15637`, `Bind=0.0.0.0`
   - `PublicUrl=$LIVEMAP_PUBLIC_URL`, `DetectPublicAddress=0`, `AnnounceInChat=1`
   - `UpdateMs=250`, `Log=1`, `LogDiagnostics=0`
   - `Key=`: the `Key` from the existing `livemap.ini` if it has one. Otherwise 16 characters from `/dev/urandom` (alphabet `abcdefghjkmnpqrstuvwxyz23456789`). The script never prints the key.
5. If `/opt/enshrouded/server/livemap.log` is over 10 MB, keep only its last 1000 lines.
6. Always exit 0, so a map problem can never stop the game server from starting.

Flux substitutes `${...}` in every rendered manifest, so the script must not contain `${`. Use `$var` only, and get the version without the `v` with `sed`.

### 2. `cluster/apps/enshrouded/enshrouded/app/values.yaml`

- Env:
  - `WINEDLLOVERRIDES: "iphlpapi=n,b"`
  - `BOOTSTRAP_HOOK: bash /opt/livemap/livemap-install.sh`
  - `LIVEMAP_PUBLIC_URL: https://enshrouded-map.${EXTERNAL_DOMAIN}`
  - The version and hash pair. The shared "Annotated YAML release tag with asset sha256" Renovate manager in repo-operator `annotated.json5` bumps both together:

    ```yaml
    # renovate: depName=oggii/enshrouded-livemap datasource=github-release-attachments digest=sha256
    LIVEMAP_VERSION: "v1.7.0"
    LIVEMAP_SHA256: "edb1c346b3d245307239de8b2561713c04d2b49170011b98f3e718c760d325b9"
    ```

- Container port `map`: 15637/TCP.
- New Service `map`: ClusterIP, TCP 15637, controller `enshrouded`. The `game` LoadBalancer stays UDP only.
- Persistence:
  - A `livemap-script` ConfigMap mount at `/opt/livemap` (mode 0755, read-only).
  - `saves` also mounts `subPath: livemap` at `/opt/enshrouded/server/livemap`, so the map history sits on the backed-up PVC. The image's hourly backup zips only `world*.ksd`, so this does not grow the save zips. The entrypoint's recursive chown of `/opt/enshrouded` and of `SERVER_SAVE_DIR` covers the new folder.

### 3. `cluster/apps/enshrouded/enshrouded/app/network-policies.yaml`

Add `allow-traefik-livemap-ingress`: TCP 15637 from `k8s:io.kubernetes.pod.namespace: traefik`, `k8s:app.kubernetes.io/name: traefik`. Copy the Foundry `allow-traefik-ingress` shape.

### 4. Traefik: `cluster/apps/traefik/traefik/ingress/enshrouded/`

- `certificates.yaml`: a cert-manager `Certificate` for `enshrouded-map.${EXTERNAL_DOMAIN}` in namespace `enshrouded`.
- `ingress-routes.yaml`: an `IngressRoute` on `websecure` for `` Host(`enshrouded-map.${EXTERNAL_DOMAIN}`) `` to Service `enshrouded-map` port 15637, with the external-dns hostname and `${TRAEFIK_IP4}` target annotations, so LAN clients go straight to Traefik. No `compress` middleware: the DLL sends pre-gzipped data files itself, and `/events` is a stream.
- `kustomization.yaml`, and add `./enshrouded` to `cluster/apps/traefik/traefik/ingress/kustomization.yaml`.

### 5. Cloudflare: `infra/terraform/cloudflare/tunnel.tf`

Add a `tunnel_routes` entry, in alphabetical order:

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
- Add a "Live map" section: what the map is, its URL, and that players get the link (with the key) in game chat when they join. Also: the hook and where files live, how bumps work (Renovate moves version and hash together; a bad hash keeps the last good version), and how to change the key (delete the `Key=` line from `livemap.ini`, then restart the pod).
- Add the WAF note: only visitors in Australia can open it from outside the LAN.

## Order

1. One commit with sections 1 to 4 and 6, plus the Terraform route (5). Flux applies the cluster side. The route stays dark until the Terraform run is applied.
2. The owner confirms the Cloudflare Terraform Cloud run.
3. Check the map (gates below).

## Riskiest assumption

That the DLL loads under this image's Wine, finds what it needs in the current game build, and leaves the server healthy.

Proof after deploy:

- `livemap.log` shows `web map listening on 0.0.0.0:15637 (TCP)`, and no hook reports "not found".
- In the pod, `curl` to `http://127.0.0.1:15637/state` with the key read from `livemap.ini` into a shell variable returns 200. Print only the status code, never the key.
- Without the key, `https://enshrouded-map.${EXTERNAL_DOMAIN}/` returns the DLL's 403 body ("Open the map with ?key=").
- The server is RUNNING. Tick time in the Enshrouded Grafana dashboard (vlogs `[ecss] Stats:` recording rules) shows no change against the hour before.

Rollback: remove `WINEDLLOVERRIDES`. Wine then loads its builtin `iphlpapi`, and the DLL on disk does nothing.

## Gates for the builder

- Render the enshrouded and traefik Kustomizations with the cluster variables substituted, and diff the script in the ConfigMap against the file. They must match byte for byte.
- `shellcheck` passes on the script.
- Every failure path in the script ends with exit 0.
- `terraform fmt -check` and `terraform validate` pass in `infra/terraform/cloudflare`.
