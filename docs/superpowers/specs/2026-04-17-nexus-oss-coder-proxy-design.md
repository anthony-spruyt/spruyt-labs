# Nexus OSS for Coder Workspace Builds — Design

**Issue:** [#968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)
**Status:** Approved (brainstorm complete, revised after research)
**Date:** 2026-04-17

## Summary

Deploy **Sonatype Nexus Repository 3 OSS** in-cluster as an apt + docker artifact proxy for Coder workspace (envbuilder) builds and developer workstations. Replaces rate-limited public Ubuntu mirror fetches and anonymous Docker Hub / ghcr.io / mcr.microsoft.com pulls with LAN-local cached reads. Also replaces the ghcr-hosted envbuilder kaniko layer cache with an in-cluster hosted docker repo.

Explicitly scoped to **Coder workspace builds and developer workstations**. Cluster image pulls (kubelet + Spegel), Flux OCIRepositories, and all other workloads remain on direct upstream paths. Nexus being down must never block cluster bootstrap or Flux reconciliation.

## Motivation

Envbuilder builds are I/O-bound on two independent issues:

1. **apt downloads** from `archive.ubuntu.com` — ~100-300 kB/s per-IP rate limit; kaniko wipes `/var/lib/apt/lists/` per layer, re-fetching 40MB+ indices for every feature install. Mirror sync races (see #967) intermittently fail builds.
2. **Container image pulls** — anonymous Docker Hub rate limits; base image `mcr.microsoft.com/devcontainers/base:jammy` + nine `ghcr.io/devcontainers/*` features pulled fresh per rebuild.

Nexus OSS 3 solves both via apt proxy (native HTTPS pass-through) and docker proxy repos. The same deployment hosts the kaniko layer cache on LAN-local Ceph storage, replacing ghcr.

## Architecture

**Chart:** `bjw-s-labs/app-template` (repo convention — used by 30+ apps). Sonatype's own chart is deprecated and shipped without support for our requirements (multi-port service, StatefulSet mode); app-template is a declarative wrapper that gives full control over StatefulSet, Service, ConfigMaps, initContainers, probes, and securityContext while staying Helm-managed.

**Workload:** StatefulSet with one replica, image `sonatype/nexus3` pinned by digest, Renovate-tracked. 100Gi Ceph RBD PVC for `/nexus-data` (blob store + DB). Expandable via `allowVolumeExpansion`.

**TLS strategy:** Nexus listens **plain HTTP only** on `:8081` inside the cluster. **Traefik terminates TLS externally** using a cert-manager-issued ZeroSSL cert, matching repo convention for every other LAN-only app. No Jetty native TLS, no PKCS12 keystore, no in-pod cert distribution.

**Docker routing strategy:** Sonatype's documented ["subdomain + path-prefix reverse-proxy strategy"][docker-rp]. All docker repos served from the single Nexus HTTP port under `/repository/<name>/`. Traefik routes `nexus-docker.lan.${EXTERNAL_DOMAIN}` → Nexus. Avoids the multi-port Jetty complexity Sonatype explicitly warns against.

[docker-rp]: https://help.sonatype.com/en/docker-repository-reverse-proxy-strategies.html

**DNS split-horizon:** CoreDNS rewrite via Talos `extraManifests` — in-cluster pods resolve `nexus.lan.${EXTERNAL_DOMAIN}` directly to Nexus ClusterIP (single pod hop, plain HTTP). External clients (dev PC) resolve via Technitium LAN DNS → Traefik LoadBalancer IP → TLS terminated at Traefik → plain HTTP to Nexus. Both paths in-cluster only; not routed through Cloudflare Tunnel.

**CoreDNS lives in Talos, not Flux**, to avoid bootstrap chicken-egg (Flux needs DNS to start).

## Components

### Namespace and workload

- `cluster/apps/nexus-system/namespace.yaml` — namespace with repo-standard labels (PSA `restricted` — app-template defaults align, see existing vaultwarden pattern)
- `cluster/apps/nexus-system/nexus/app/release.yaml` — HelmRelease referencing `app-template` OCIRepository
- `cluster/apps/nexus-system/nexus/app/values.yaml` — StatefulSet + PVC + Service + probes + initContainer (chown /nexus-data to UID 200), all expressed via app-template schema
- `cluster/apps/nexus-system/nexus/app/vpa.yaml` — recommendation-only VPA
- `cluster/apps/nexus-system/nexus/app/pod-monitor.yaml` — VMPodScrape for `/service/metrics/prometheus` (anonymous after provisioning grants `nx-metrics-all` to the anonymous role)

### nexus.properties (mounted config)

Minimal override, single purpose: enable the `anonymous` user and set the base URL. TLS settings omitted (plain HTTP). Delivered via app-template `persistence.configmap` mount at `/nexus-data/etc/nexus.properties`.

### Repository provisioning

A Kubernetes Job created after Nexus is writable, running a `curlimages/curl` container. The Job name is hash-suffixed via `configMapGenerator` so it re-runs whenever the provisioning script changes. RBAC kept minimal (no cluster API access needed — secrets injected via `valueFrom.secretKeyRef`).

**Repositories created:**

| Name | Type | Upstream / Purpose |
| --- | --- | --- |
| `apt-ubuntu-proxy` | apt proxy | `http://archive.ubuntu.com/ubuntu/` (jammy + noble) |
| `apt-cli-github` | apt proxy | `https://cli.github.com/packages/` |
| `apt-nodesource` | apt proxy | `https://deb.nodesource.com/` |
| `apt-hashicorp` | apt proxy | `https://apt.releases.hashicorp.com/` |
| `apt-launchpad` | apt proxy | `https://ppa.launchpadcontent.net/` |
| `docker-hub-proxy` | docker proxy | `https://registry-1.docker.io` (Nexus holds dockerhub PAT) |
| `ghcr-proxy` | docker proxy | `https://ghcr.io` (Nexus holds ghcr PAT) |
| `mcr-proxy` | docker proxy | `https://mcr.microsoft.com` (anonymous upstream) |
| `envbuilder-cache` | docker hosted | kaniko layer cache (replaces current `ghcr.io/anthony-spruyt/envbuilder-cache/*` path) |
| `docker-group` | docker group | Unions the 4 docker repos above; served at `/repository/docker-group/` |

**Anonymous access** granted on all proxy/group repos and the metrics endpoint. Write access (to `envbuilder-cache`) requires the authenticated user whose credentials ship with envbuilder via `ENVBUILDER_DOCKER_CONFIG_BASE64`.

### Secrets

- `cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml` — admin password (consumed by Nexus first boot via `NEXUS_SECURITY_INITIAL_PASSWORD` env, and by provisioning Job) + `admin-username: admin`
- `cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml` — dockerhub PAT, ghcr PAT (consumed by provisioning Job when creating proxy repos)
- `cluster/apps/nexus-system/nexus/app/nexus-envbuilder-credentials.sops.yaml` — dockerconfigjson for envbuilder: auth entry for `nexus-docker.lan.${EXTERNAL_DOMAIN}` (cache push target)

### Network policy

Single `CiliumNetworkPolicy`:

**Ingress allowed to Nexus pod (endpointSelector `app.kubernetes.io/name: nexus`):**
- `coder-system` namespace pods → `:8081`
- `traefik` namespace pods → `:8081`
- `observability` namespace, `app.kubernetes.io/name: vmagent` → `:8081`
- `nexus-system` namespace, `app.kubernetes.io/name: nexus-provisioner` → `:8081`

**Egress from Nexus pod:**
- `kube-dns` (standard)
- `world:443` (upstream registries + HTTPS apt hosts)
- `world:80` (archive.ubuntu.com, security.ubuntu.com)

### Traefik ingress (external access)

`cluster/apps/traefik/traefik/ingress/nexus-system/`:

- `kustomization.yaml`
- `ingress-routes.yaml` — two standard `IngressRoute` entries, both TLS-terminated at Traefik, plain HTTP to Nexus svc:
  - `nexus.lan.${EXTERNAL_DOMAIN}` → `nexus.nexus-system.svc:8081` (UI + apt + REST)
  - `nexus-docker.lan.${EXTERNAL_DOMAIN}` → `nexus.nexus-system.svc:8081` (docker clients; path rewrite if needed so `docker pull nexus-docker.lan.xyz/alpine` resolves to `/repository/docker-group/alpine`)
- `certificates.yaml` — cert-manager Certificate at `nexus-lan-${EXTERNAL_DOMAIN/./-}-tls`, issuer `zerossl-production`, SANs `nexus.lan.${EXTERNAL_DOMAIN}` + `nexus-docker.lan.${EXTERNAL_DOMAIN}`
- `lan-ip-whitelist` middleware applied per repo convention

### CoreDNS split-horizon (in-cluster)

Talos `extraManifests` ConfigMap override for CoreDNS adds rewrite rules before the `kubernetes` plugin:

```text
rewrite name exact nexus.lan.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
rewrite name exact nexus-docker.lan.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
```

In-cluster pods resolve the FQDN directly to Nexus ClusterIP and hit Nexus on plain HTTP `:8081`, skipping Traefik. Traefik ingress remains for external (dev PC LAN) access.

**Per Talos-managed model:** regenerate + apply Talos configs after editing `talos/talconfig.yaml` (see `.claude/memory/feedback_talos_genconfig.md`).

## Data flow

**Workspace build, cold cache:**

```text
envbuilder pod
  ├── resolves nexus-docker.lan.${EXTERNAL_DOMAIN} via CoreDNS → Nexus ClusterIP
  ├── kaniko mirror: KANIKO_REGISTRY_MIRROR=nexus-docker.lan.${EXTERNAL_DOMAIN}/repository/docker-group
  ├── pulls base image → Nexus:8081/repository/docker-group/... → (miss) → upstream → cached
  ├── pulls feature images → same path → cached
  ├── apt update → nexus.lan.${EXTERNAL_DOMAIN}/repository/apt-ubuntu-proxy/... → cached
  ├── apt install (feature HTTPS repo) → nexus.lan.${EXTERNAL_DOMAIN}/repository/apt-nodesource/... → cached
  └── pushes layer cache → ENVBUILDER_CACHE_REPO=nexus-docker.lan.${EXTERNAL_DOMAIN}/repository/envbuilder-cache/<workspace>
```

**Workspace build, warm cache:** all hits served from Nexus blob store on Ceph.

**Dev PC apt/docker:** same endpoints via Technitium → Traefik LB → Nexus. Traefik terminates TLS; rest identical.

## Consumer config changes

### `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- Add `KANIKO_REGISTRY_MIRROR=nexus-docker.lan.${EXTERNAL_DOMAIN}/repository/docker-group`
- Rewrite `ENVBUILDER_DOCKER_CONFIG_BASE64` — standard docker `config.json` auth entries for `nexus-docker.lan.${EXTERNAL_DOMAIN}` (anonymous read + authenticated push credentials for cache hosted repo). No `registry-mirrors` key (daemon-only).
- Remove existing upstream dockerhub/ghcr PATs after cutover (PR 3).

### `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

Line 58: change `ENVBUILDER_CACHE_REPO` from
```hcl
"ghcr.io/anthony-spruyt/envbuilder-cache/${data.coder_workspace.me.name}"
```
to
```hcl
"nexus-docker.lan.${var.external_domain}/repository/envbuilder-cache/${data.coder_workspace.me.name}"
```

Add `KANIKO_REGISTRY_MIRROR` env var alongside.

### Envbuilder apt proxy

envbuilder's `KANIKO_REGISTRY_MIRROR` does NOT cover runtime apt (run inside the built devcontainer). Apt proxy must be baked into the devcontainer Dockerfile.

**Cluster path:** the Coder devcontainer template (`coder-template-sync/app/templates/devcontainer/`) is Terraform-rendered — `${var.external_domain}` interpolates at template-render time, producing a concrete Dockerfile the envbuilder sees. Add to that Dockerfile:

```dockerfile
RUN echo 'Acquire::https::Proxy "https://nexus.lan.${external_domain}/repository/apt-ubuntu-proxy/";' \
    > /etc/apt/apt.conf.d/01proxy
```

Plus `/etc/apt/sources.list.d/*.list` entries pointing at the four passthrough apt repos for HTTPS upstreams used by devcontainer features.

### Local `.devcontainer/Dockerfile` (this repo)

**Out of scope for PR 1-3.** Deferred to a follow-up: the local Dockerfile needs a build `ARG EXTERNAL_DOMAIN` + `devcontainer.json` build-args referencing `${localEnv:EXTERNAL_DOMAIN}` so the proxy URL substitutes at `docker build` time on the dev PC.

### `cluster/flux/meta/repositories/oci/ghcr-docker-config-secrets.sops.yaml`

**No change.** Flux OCIRepository auth stays on direct ghcr.io — not routed through Nexus (chicken-egg avoidance).

## Rollout order

1. **PR 1 — Nexus stack.** Namespace + app-template HelmRelease + PVC + CoreDNS rewrite via Talos + provisioning Job + CNP + Traefik ingress + VMPodScrape + VPA. No consumer changes. Verify: namespace PSA-restricted compliant, Nexus up on 8081, UI reachable from dev PC, all 10 repos provisioned, anonymous access works for reads + metrics.
2. **PR 2 — Coder integration.** Update `main.tf` `ENVBUILDER_CACHE_REPO` + `KANIKO_REGISTRY_MIRROR`. Rewrite `coder-workspace-env.sops.yaml` docker config. Add apt proxy to the Coder template Dockerfile. Rebuild one test workspace end-to-end, verify logs show Nexus endpoints.
3. **PR 3 — Cleanup.** After 3+ successful workspace rebuilds, remove legacy upstream PATs from `coder-workspace-env.sops.yaml`. Close #968.
4. **Follow-up (separate issue):** Local `.devcontainer/Dockerfile` apt proxy via build ARG.

## Rollback

Per-PR revert. No data migration. Nexus blob store is regeneratable (cache). Dropping Nexus from envbuilder via revert returns envbuilder to direct upstream paths.

## Observability

Nexus exposes Prometheus metrics at `/service/metrics/prometheus`. Provisioning Job grants `nx-metrics-all` to the `anonymous` role so VMPodScrape can fetch without basic auth. VMPodScrape selects on `app.kubernetes.io/name: nexus` with port name `http`.

## Risk assessment

**Low.** Stateless cache (blob store regeneratable), no cluster-critical dependency, PVC-backed, no auth model changes to existing workloads, no cloudflared exposure. Explicitly kept off the bootstrap / Flux / kubelet critical path. CoreDNS rewrite edit is the only Talos-config change — it adds two rewrite entries and does not remove or alter existing CoreDNS behavior.

## Open items (all resolvable during plan; carried forward for explicit call-out)

- **Docker path-rewrite via Traefik middleware** — whether `docker pull nexus-docker.lan.xyz/alpine:3` needs a Traefik StripPrefix/ReplacePath middleware to hit `/repository/docker-group/alpine:3`, or whether Nexus's docker connector handles the mapping natively when served on a subdomain. Validate during PR 1.
- **app-template schema specifics** — exact key paths for StatefulSet + multi-port service + config-map-mounted nexus.properties. Refer to `bjw-s` common chart values schema.
- **nx-metrics-all grant mechanism** — REST API call shape for granting a privilege to the anonymous role. Validate against Nexus 3 Security API docs during provisioning Job authoring.
