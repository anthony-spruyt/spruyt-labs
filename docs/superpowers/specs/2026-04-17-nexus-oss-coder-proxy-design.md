# Nexus OSS for Coder Workspace Builds — Design

**Issue:** [#968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)
**Status:** Approved (brainstorm complete, revised twice after research + review)
**Date:** 2026-04-17

## Summary

Deploy **Sonatype Nexus Repository 3 OSS** in-cluster as an apt + docker artifact proxy for Coder workspace (envbuilder) builds and developer workstations. Replaces rate-limited public Ubuntu mirror fetches and anonymous Docker Hub / ghcr.io / mcr.microsoft.com pulls with LAN-local cached reads. Also replaces the ghcr-hosted envbuilder kaniko layer cache with an in-cluster hosted docker repo.

Explicitly scoped to **Coder workspace builds and developer workstations**. Cluster image pulls (kubelet + Spegel), Flux OCIRepositories, and all other workloads remain on direct upstream paths. Nexus being down must never block cluster bootstrap or Flux reconciliation.

## Motivation

Envbuilder builds are I/O-bound on two independent issues:

1. **apt downloads** from `archive.ubuntu.com` — ~100-300 kB/s per-IP rate limit; kaniko wipes `/var/lib/apt/lists/` per layer, re-fetching 40MB+ indices for every feature install. Mirror sync races (see #967) intermittently fail builds.
2. **Container image pulls** — anonymous Docker Hub rate limits; base image `mcr.microsoft.com/devcontainers/base:jammy` + nine `ghcr.io/devcontainers/*` features pulled fresh per rebuild.

Nexus OSS 3 solves both via apt proxy (native HTTPS pass-through) and docker proxy repos. Same deployment hosts the kaniko layer cache on LAN-local Ceph storage, replacing ghcr.

## Architecture

**Chart:** `bjw-s-labs/app-template` (repo convention — 30+ apps use it, including vaultwarden which is the closest structural match: StatefulSet + PVC + reloader). Sonatype's own chart is deprecated and hobbled (no multi-port Service, StatefulSet mode unsupported).

**Workload:** StatefulSet with one replica, image `sonatype/nexus3` pinned by digest, Renovate-tracked. 100Gi Ceph RBD PVC for `/nexus-data` (blob store + DB). Expandable via `allowVolumeExpansion`.

**TLS strategy:** Nexus listens **plain HTTP only** — no Jetty TLS, no PKCS12 keystore, no internal CA. Rationale: inside-cluster pod-to-pod traffic is already Cilium eBPF-routed with CNP isolation; TLS inside a CNP-locked homelab cluster adds plumbing for zero real-world risk reduction. Standard K8s pattern — virtually every other app in the repo talks plain HTTP service-to-service.

- **Workspace pods** (in-cluster) → plain HTTP to `nexus.nexus-system.svc.cluster.local` on ports 8081 (apt/REST/UI) and 8082 (docker). `ENVBUILDER_INSECURE=true` tells kaniko to accept plain-HTTP registries.
- **Dev PC** → `https://nexus.lan.${EXTERNAL_DOMAIN}` via Technitium LAN DNS → Traefik LB → TLS terminated at Traefik with ZeroSSL cert → plain HTTP to Nexus svc.

No CoreDNS rewrite. No Talos machine-config edit. No internal CA. Simpler by deletion.

**Docker routing:** Sonatype's documented
["subdomain + dedicated connector"][docker-rp] strategy. The `docker-group`
repo is configured with its own `docker.httpPort: 8082` — Nexus spins up a
second Jetty connector serving OCI registry v2 protocol at `/v2/` (host-root).
Exposed as a second Service port. No Traefik path-rewrite needed; docker
clients pull `nexus-docker.lan.${EXTERNAL_DOMAIN}/alpine:3` and that lands
on `/v2/alpine/manifests/...` at Nexus port 8082, which serves the group's
contents.

[docker-rp]: https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html

## Components

### Namespace and workload

- `cluster/apps/nexus-system/namespace.yaml` — PSA `restricted`
- `cluster/apps/nexus-system/nexus/app/release.yaml` — HelmRelease referencing `app-template` OCIRepository (mirror vaultwarden's shape: `install`, `upgrade`, `driftDetection`, `releaseName` all set)
- `cluster/apps/nexus-system/nexus/app/values.yaml` — StatefulSet on app-template, multi-port Service (8081 + 8082), PVC, probes, reloader annotation. `fsGroup: 200` with `fsGroupChangePolicy: OnRootMismatch` handles `/nexus-data` ownership (no initContainer needed).
- `cluster/apps/nexus-system/nexus/app/vpa.yaml` — recommendation-only
- `cluster/apps/nexus-system/nexus/app/pod-monitor.yaml` — VMPodScrape, anonymous

### nexus.properties

Mounted via ConfigMap with `subPath` at `/nexus-data/etc/nexus.properties` (reloader-watched since name is stable, not hashed). Keys set:

```properties
application-port=8081
nexus.base.url=https://nexus.lan.${EXTERNAL_DOMAIN}
nexus.scripts.allowCreation=false
```

`nexus.base.url` makes Nexus emit `https://` absolute URLs in docker Www-Authenticate realms and API responses, matching the externally-visible scheme (which is what docker clients and apt actually see via Traefik).

### Repository provisioning

Kubernetes Job created post-deploy, running `curlimages/curl`. Script stored as a `configMapGenerator`-hashed ConfigMap; Job volume references it — Kustomize name-reference rewrites both the HelmRelease's valuesFrom AND the Job's volume configMap name to the hashed form via explicit `kustomizeconfig.yaml` entries.

When `provision.sh` changes, the ConfigMap hash changes → Job spec changes → Flux re-applies → `kustomize.toolkit.fluxcd.io/force: "true"` annotation triggers delete+recreate of the immutable Job.

**Repositories created:**

| Name | Type | Upstream / Purpose |
| --- | --- | --- |
| `apt-ubuntu-proxy` | apt proxy | `http://archive.ubuntu.com/ubuntu/` (jammy; noble added later if needed via separate repo) |
| `apt-cli-github` | apt proxy | `https://cli.github.com/packages/` |
| `apt-nodesource` | apt proxy | `https://deb.nodesource.com/` |
| `apt-hashicorp` | apt proxy | `https://apt.releases.hashicorp.com/` |
| `apt-launchpad` | apt proxy | `https://ppa.launchpadcontent.net/` |
| `docker-hub-proxy` | docker proxy | `https://registry-1.docker.io` (Nexus holds dockerhub PAT) |
| `ghcr-proxy` | docker proxy | `https://ghcr.io` (Nexus holds ghcr PAT) |
| `mcr-proxy` | docker proxy | `https://mcr.microsoft.com` (anonymous) |
| `envbuilder-cache` | docker hosted | kaniko layer cache; **not** a group member (workspace-private, must not leak via group) |
| `docker-group` | docker group | Members: `docker-hub-proxy`, `ghcr-proxy`, `mcr-proxy`. Connector: `httpPort: 8082`. |

**Anonymous access** granted on proxy/group repos + metrics. The
provisioning Job grants privileges via **GET → merge → PUT** on the
`anonymous` role to avoid clobbering upstream defaults: existing privileges
are read, the 4 new privileges are added (deduped), and the full role is
PUT back. The four added: `nx-repository-view-*-*-read`,
`nx-repository-view-*-*-browse`, `nx-metrics-all`, `nx-healthcheck-read`.
Write access to `envbuilder-cache` uses admin credentials (follow-up issue:
replace with dedicated scoped user).

### Secrets

- `nexus-admin.sops.yaml` — `admin-username: admin` + `admin-password: <random>`
- `nexus-upstream-creds.sops.yaml` — dockerhub PAT, ghcr PAT

Envbuilder docker config is rewritten inline in `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml` (Task 10) — no dedicated new SOPS file.

### Network policy

`CiliumNetworkPolicy` with tighter selectors than namespace-wide:

**Ingress to Nexus pod (endpointSelector `app.kubernetes.io/name: nexus`):**
- `coder-system`, pods with label `com.coder.resource: "true"` → `:8081`, `:8082`
- `traefik` namespace, `k8s:app.kubernetes.io/name: traefik` → `:8081`, `:8082`
- `observability`, `k8s:app.kubernetes.io/name: vmagent` → `:8081`
- `nexus-system`, `k8s:app.kubernetes.io/name: nexus-provisioner` → `:8081`

**Egress from Nexus pod:** kube-dns, `world:443` (HTTPS upstreams), `world:80` (ubuntu mirror).

### Traefik ingress (external access)

`cluster/apps/traefik/traefik/ingress/nexus-system/`:

- `certificates.yaml` — cert-manager Certificate, issuer `${CLUSTER_ISSUER}` (resolves to `zerossl-production` per `cluster-settings` ConfigMap), SANs `nexus.lan.${EXTERNAL_DOMAIN}` + `nexus-docker.lan.${EXTERNAL_DOMAIN}`, secretName `nexus-${EXTERNAL_DOMAIN/./-}-tls`
- `ingress-routes.yaml` — two `IngressRoute` entries, both TLS-terminated by Traefik with the above cert:
  - `nexus.lan.${EXTERNAL_DOMAIN}` → `nexus.nexus-system.svc:8081` (UI + apt + REST). Middlewares: `lan-ip-whitelist`, `compress`.
  - `nexus-docker.lan.${EXTERNAL_DOMAIN}` → `nexus.nexus-system.svc:8082` (docker connector, serves OCI v2 at host-root). Middleware: `lan-ip-whitelist`. **No path rewrite** — Nexus's dedicated docker connector serves `/v2/*` directly.
- `kustomization.yaml`

## Data flow

**Workspace build, cold cache:**

```text
envbuilder pod (in-cluster)
  ├── ENVBUILDER_INSECURE=true
  ├── KANIKO_REGISTRY_MIRROR=nexus.nexus-system.svc.cluster.local:8082
  ├── pulls base image → http://nexus...svc:8082/v2/... → (miss) → mcr.microsoft.com → cached
  ├── pulls feature images → same path → cached (ghcr via ghcr-proxy, dockerhub via docker-hub-proxy)
  ├── apt update → http://nexus...svc:8081/repository/apt-ubuntu-proxy/... → cached
  ├── apt install (HTTPS upstream feature) → http://nexus...svc:8081/repository/apt-nodesource/... → cached
  └── pushes layer cache → ENVBUILDER_CACHE_REPO=nexus...svc:8082/v2/envbuilder-cache/<workspace>
```

**Workspace build, warm cache:** all hits served from Nexus blob store on Ceph.

**Dev PC apt/docker:** `https://nexus.lan.${EXTERNAL_DOMAIN}/repository/<name>/...` via Technitium → Traefik TLS termination → plain HTTP to Nexus. Apt sees valid TLS, docker client talks to `nexus-docker.lan.${EXTERNAL_DOMAIN}` and Traefik routes to `:8082`.

## Consumer config changes

### `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- Add `KANIKO_REGISTRY_MIRROR=nexus.nexus-system.svc.cluster.local:8082`
- Add `ENVBUILDER_INSECURE=true` (allows plain-HTTP mirror + cache repo)
- Rewrite `ENVBUILDER_DOCKER_CONFIG_BASE64` — `auths` entry for `nexus.nexus-system.svc.cluster.local:8082` with admin creds (for cache push). No `registry-mirrors` key — that's a daemon config key, not used by kaniko.
- Leave existing dockerhub/ghcr PATs in place until Task 13 cleanup (PR 3).

### `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

Line 58 change:
```hcl
"ENVBUILDER_CACHE_REPO" : "nexus.nexus-system.svc.cluster.local:8082/envbuilder-cache/${data.coder_workspace.me.name}",
```

Add in same env map: `"KANIKO_REGISTRY_MIRROR" : "nexus.nexus-system.svc.cluster.local:8082"` and `"ENVBUILDER_INSECURE" : "true"`.

### Envbuilder apt proxy (runtime apt inside devcontainer)

Envbuilder's `KANIKO_REGISTRY_MIRROR` only covers image pulls during build. Runtime apt inside the workspace is separate. Inject apt proxy via the Coder devcontainer template Dockerfile (Terraform-rendered; `${external_domain}` substitutes at template render time if needed, though for the plain-HTTP svc path no substitution is required):

```dockerfile
RUN echo 'Acquire::http::Proxy "http://nexus.nexus-system.svc.cluster.local:8081/repository/apt-ubuntu-proxy/";' \
    > /etc/apt/apt.conf.d/01proxy
```

Plus four additional `/etc/apt/sources.list.d/*.list` entries pointing at the HTTPS-upstream passthrough apt repos (cli.github, nodesource, hashicorp, launchpad) as features install them.

### Local `.devcontainer/Dockerfile` (this repo)

**Out of scope.** Handled by dev PC directly resolving `nexus.lan.${EXTERNAL_DOMAIN}` via Technitium in a follow-up.

### `cluster/flux/meta/repositories/oci/ghcr-docker-config-secrets.sops.yaml`

**No change.** Flux OCIRepository auth stays direct.

## Rollout order

1. **PR 1 — Nexus stack.** Namespace + HelmRelease + PVC + provisioning Job + CNP + VPA + VMPodScrape + Traefik ingress. No consumer changes. Verify: StatefulSet Ready, 10 repos provisioned, anonymous access for reads + metrics works, UI loads from dev PC over TLS, `curl` smoke tests against apt and docker endpoints succeed.
2. **PR 2 — Coder integration.** Update `main.tf` env. Rewrite `coder-workspace-env.sops.yaml`. Add apt proxy to Coder template Dockerfile. Rebuild 3 workspaces end-to-end; confirm logs show Nexus endpoints.
3. **PR 3 — Cleanup.** Remove legacy upstream PATs from `coder-workspace-env.sops.yaml`. Close #968.

## Rollback

Per-PR revert. Stateless cache (regenerable). Dropping Nexus from envbuilder via revert → envbuilder returns to direct upstream paths.

## Observability

Nexus exposes `/service/metrics/prometheus`. Provisioning Job grants `nx-metrics-all` to anonymous. VMPodScrape selects on `app.kubernetes.io/name: nexus` + port name `http` (8081).

## Risk assessment

**Low.** Stateless cache, no cluster-critical dependency, PVC-backed, no auth model changes, no cloudflared exposure, explicitly kept off bootstrap / Flux / kubelet critical path. No Talos machine-config changes. No CoreDNS changes.
