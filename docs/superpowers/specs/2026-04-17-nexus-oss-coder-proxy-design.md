# Nexus OSS for Coder Workspace Builds — Design

**Issue:** [#968](https://github.com/anthony-spruyt/spruyt-labs/issues/968)
**Status:** Approved (brainstorm complete)
**Date:** 2026-04-17

## Summary

Deploy **Sonatype Nexus Repository OSS** in-cluster as an apt + docker artifact proxy for Coder workspace (envbuilder) builds. Replaces rate-limited public Ubuntu mirror fetches and anonymous Docker Hub / ghcr.io / mcr.microsoft.com pulls with LAN-local cached reads. Also replaces the ghcr-hosted envbuilder kaniko layer cache with an in-cluster hosted docker repo.

Explicitly scoped to **Coder workspace builds and developer workstations**. Cluster image pulls (kubelet + Spegel), Flux OCIRepositories, and all other workloads remain on direct upstream paths. Nexus being down must never block cluster bootstrap or Flux reconciliation.

## Motivation

Envbuilder builds in Coder workspaces are I/O-bound on two independent issues:

1. **apt downloads** from `archive.ubuntu.com` — ~100-300 kB/s per-IP rate limit; kaniko wipes `/var/lib/apt/lists/` per layer, re-fetching 40MB+ indices for every feature install. Mirror sync races (see #967) intermittently fail builds.
2. **Container image pulls** — anonymous Docker Hub rate limits; base image `mcr.microsoft.com/devcontainers/base:jammy` + nine `ghcr.io/devcontainers/*` features pulled fresh per rebuild.

Nexus OSS solves both in one deployment via native HTTPS-upstream support (`PassThroughPattern`) and docker proxy repos. Same deployment also hosts the kaniko layer cache on LAN-local Ceph storage, replacing ghcr.

## Architecture

Single-replica StatefulSet running `sonatype/nexus-repository-manager` (official Helm chart) in a new `nexus-system` namespace. Jetty configured for native TLS on internal listeners (`:8443` apt/REST/UI, `:5443` docker) using a cert-manager-issued ZeroSSL certificate. 100Gi Ceph RBD PVC for blob store (expandable via `allowVolumeExpansion`). Nexus's internal database lives on the same PVC.

Consumer traffic uses a **single FQDN per service** (`nexus.${EXTERNAL_DOMAIN}`, `nexus-docker.${EXTERNAL_DOMAIN}`) via split-horizon DNS:

- **In-cluster pods** resolve via CoreDNS rewrite directly to the Nexus ClusterIP — single pod-hop, TLS terminated at Nexus.
- **External clients** (dev PCs on LAN) resolve via Technitium to the Traefik LoadBalancer IP, go through Traefik to Nexus.

Both paths use the same public ZeroSSL cert, so the trust story is identical on both sides. Not routed through Cloudflare tunnel — LAN-only.

## Components

### Namespace and deployment

- `cluster/apps/nexus-system/namespace.yaml` — namespace with standard PSA labels
- `cluster/apps/nexus-system/nexus/app/release.yaml` — HelmRelease, official Sonatype chart pinned to exact version
- `cluster/apps/nexus-system/nexus/app/values.yaml` — chart values via `configMapGenerator` (Jetty TLS properties, resource requests, PVC config)
- `cluster/apps/nexus-system/nexus/app/vpa.yaml` — recommendation-only VPA
- `cluster/apps/nexus-system/nexus/app/pod-monitor.yaml` — VMPodScrape for `/service/metrics/prometheus`

### TLS

- `cluster/apps/nexus-system/nexus/app/certificate.yaml` — cert-manager `Certificate` resource issued by `zerossl-production` ClusterIssuer with SANs:
  - `nexus.${EXTERNAL_DOMAIN}`
  - `nexus-docker.${EXTERNAL_DOMAIN}`
- Secret rendered as TLS + PKCS12 keystore (cert-manager keystore feature) for Jetty consumption
- Jetty config mounted via ConfigMap: enables HTTPS on `:8443`, docker HTTPS on `:5443`

### Repository provisioning

A one-shot post-deploy Kubernetes Job creates repositories via the Nexus REST API. Idempotent (checks for existence first, uses `PUT` semantics where supported). Tolerates Nexus not-yet-writable at startup via retry loop against `/service/rest/v1/status/writable`.

- `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml` — Job manifest, runs on each Flux reconcile where spec differs (uses Flux hash-in-name or a hash-based `job-name`)
- `cluster/apps/nexus-system/nexus/app/provision-repos-rbac.yaml` — ServiceAccount + minimal Role (read admin + upstream creds secrets)

Job uses in-cluster service DNS (`nexus.nexus-system.svc.cluster.local`) — plain HTTP on :8081 internally is fine for provisioning traffic that never leaves the namespace.

Repositories created:

| Name | Type | Upstream / Purpose |
| --- | --- | --- |
| `apt-ubuntu-proxy` | apt proxy | `archive.ubuntu.com` + `security.ubuntu.com` |
| `apt-passthrough-proxy` | apt proxy (HTTPS pass-through) | Whitelist: `cli.github.com`, `deb.nodesource.com`, `apt.releases.hashicorp.com`, `ppa.launchpadcontent.net` |
| `docker-hub-proxy` | docker proxy | `docker.io` (Nexus holds dockerhub PAT) |
| `ghcr-proxy` | docker proxy | `ghcr.io` (Nexus holds ghcr PAT) |
| `mcr-proxy` | docker proxy | `mcr.microsoft.com` (anonymous upstream) |
| `envbuilder-cache` | docker hosted | kaniko layer cache (replaces current `ghcr.io/anthony-spruyt/envbuilder-cache/*` path) |
| `docker-group` | docker group | Unions the 4 docker repos above under a single endpoint at `:5443/docker-group` |

### Secrets

- `cluster/apps/nexus-system/nexus/app/nexus-admin.sops.yaml` — initial admin password (consumed by Nexus at first boot via `NEXUS_SECURITY_INITIAL_PASSWORD` env, and by provisioning Job)
- `cluster/apps/nexus-system/nexus/app/nexus-upstream-creds.sops.yaml` — dockerhub PAT, ghcr PAT (consumed by provisioning Job to configure proxy repo auth)

Both are standard SOPS-encrypted Kubernetes Secret manifests, decrypted by Flux at reconcile time.

### Network policy

`cluster/apps/nexus-system/nexus/app/network-policies.yaml` — single `CiliumNetworkPolicy`:

**Ingress allowed from:**
- `coder-system` namespace (envbuilder workspace pods) → `:8443`, `:5443`, and `:8081` for Job
- `traefik` namespace → `:8443`, `:5443`
- `observability` namespace (vmagent) → `:8081` (metrics)
- `nexus-system` namespace (provisioning Job) → `:8081`

**Egress allowed to:**
- `kube-dns`
- `world:443` (upstream registries + HTTPS apt hosts)
- `world:80` (archive.ubuntu.com, security.ubuntu.com)

Default-deny baseline for all other traffic.

### Traefik ingress (external access)

`cluster/apps/traefik/traefik/ingress/nexus-system/`:
- `kustomization.yaml`
- `ingress-routes.yaml` — two IngressRoutes (UI+apt+REST on `nexus.${EXTERNAL_DOMAIN}`, docker on `nexus-docker.${EXTERNAL_DOMAIN}`). TLS **passthrough** to Nexus (Nexus is already serving TLS with the ZeroSSL cert; no re-termination).
- `certificates.yaml` — references the cert-manager Certificate resource (or a separate cert in Traefik namespace, depending on how TLS passthrough works with the existing Traefik config)

Note: TLS passthrough requires `IngressRouteTCP` with SNI matching in Traefik. Alternative is Traefik-terminated TLS + re-encrypt to Nexus. Final choice deferred to plan phase.

### CoreDNS rewrite (in-cluster split-horizon)

Edit to CoreDNS Corefile adds:

```text
rewrite name exact nexus.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
rewrite name exact nexus-docker.${EXTERNAL_DOMAIN} nexus.nexus-system.svc.cluster.local
```

Pods querying the FQDN receive the Nexus ClusterIP; TLS handshake succeeds because the cert has those SANs. Location of the Corefile ConfigMap to be confirmed during plan phase.

## Data flow

**Workspace build, cold cache:**

```text
envbuilder pod
  ├── resolves nexus-docker.${EXTERNAL_DOMAIN} via CoreDNS → Nexus ClusterIP
  ├── pulls base image → Nexus:5443/docker-group → (miss) → Nexus authenticates to mcr.microsoft.com → stores blob
  ├── pulls feature images → Nexus:5443/docker-group → (miss) → Nexus authenticates to ghcr.io (with PAT) → stores blob
  ├── apt update → Nexus:8443/repository/apt-ubuntu-proxy/ → (miss) → archive.ubuntu.com → cached
  ├── apt install (feature HTTPS repo) → Nexus:8443/repository/apt-passthrough-proxy/... → (miss) → HTTPS upstream → cached
  └── pushes layer cache → Nexus:5443/envbuilder-cache/<workspace-name> → stored on PVC
```

**Workspace build, warm cache:** all hits served from Nexus blob store on Ceph. Zero upstream traffic for repeated builds.

**Dev PC apt/docker:** same endpoints via Technitium → Traefik LB → Nexus. Same cache, same cert.

## Consumer config changes

### `cluster/apps/coder-system/coder/app/coder-workspace-env.sops.yaml`

- Rewrite `ENVBUILDER_DOCKER_CONFIG_BASE64` — remove upstream dockerhub/ghcr PATs; add mirror entries for `docker.io`, `ghcr.io`, `mcr.microsoft.com` pointing at `nexus-docker.${EXTERNAL_DOMAIN}`. Anonymous auth.
- Remove upstream PATs from this secret after cutover confirmed.

### `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/main.tf`

Line 58: `ENVBUILDER_CACHE_REPO` changes from
```hcl
"ghcr.io/anthony-spruyt/envbuilder-cache/${data.coder_workspace.me.name}"
```
to
```hcl
"nexus-docker.${EXTERNAL_DOMAIN}/envbuilder-cache/${data.coder_workspace.me.name}"
```

### Coder devcontainer template (envbuilder)

Add apt proxy config baked into base layer of the template Dockerfile. Uses external FQDN (TLS via Nexus native Jetty); Terraform substitutes `${var.external_domain}` at template render time, so the rendered Dockerfile seen by envbuilder has the literal domain baked in (no runtime env substitution needed):

```dockerfile
RUN echo 'Acquire::https::Proxy "https://nexus.${external_domain}/repository/apt-ubuntu-proxy/";' \
    > /etc/apt/apt.conf.d/01proxy
```

In-cluster DNS resolution of `nexus.${EXTERNAL_DOMAIN}` is handled by the CoreDNS rewrite → Nexus ClusterIP. TLS handshake against the ZeroSSL cert succeeds because the FQDN is in the cert SAN list.

HTTPS pass-through repos (`cli.github.com`, `deb.nodesource.com`, etc.) reached via Nexus URL rewrite pattern — added as separate `sources.list.d/*.list` entries pointing at `https://nexus.${external_domain}/repository/apt-passthrough-proxy/HTTPS///...`. Exact URL rewrite syntax validated during plan phase.

### Local `.devcontainer/Dockerfile` (this repo)

**Out of scope for this spec.** Dev PC workflow continues as-is initially. Once the cluster path is stable, a follow-up change will add apt proxy config via a Dockerfile `ARG` + `devcontainer.json` build-args sourcing `EXTERNAL_DOMAIN` from `${localEnv:EXTERNAL_DOMAIN}`. Tracked separately.

### `cluster/flux/meta/repositories/oci/ghcr-docker-config-secrets.sops.yaml`

**No change.** Flux OCIRepository auth stays on direct ghcr.io — not routed through Nexus (chicken-egg avoidance).

## Rollout order

Each step a separate PR to limit blast radius:

1. **PR 1 — Deploy Nexus stack.** Helm + PVC + cert + Jetty TLS config + CoreDNS rewrite + provisioning Job + NetworkPolicy + Traefik ingress + VMPodScrape. No consumer changes yet. Verify: repos provisioned, UI reachable from dev PC, apt/docker proxy endpoints serve content via `curl`.
2. **PR 2 — Coder template + workspace env.** Update `main.tf` `ENVBUILDER_CACHE_REPO`; rewrite `coder-workspace-env.sops.yaml` docker config; add apt proxy to the template Dockerfile. Rebuild one test workspace end-to-end.
3. **Cleanup PR** — Remove upstream PATs from `coder-workspace-env.sops.yaml` once Nexus stability confirmed (~1 week observation).
4. **Follow-up (out of scope, separate issue)** — Local `.devcontainer/Dockerfile` apt proxy via build ARG.

## Rollback

- **PR-level rollback**: revert the commit, Flux reconciles, workspaces fall back to prior behavior.
- **Nexus outage while live**: no automatic fallback — fix Nexus. Coder workspace rebuilds fail until Nexus recovered. Existing running workspaces unaffected (no runtime dependency). Deliberate choice (see open concerns).

## Observability

Nexus exposes Prometheus metrics at `/service/metrics/prometheus`. VMPodScrape picks these up automatically. Useful series: blob store size, proxy hit/miss ratio, REST request rate. Dashboard creation deferred (stock Nexus Grafana dashboard available, import later).

## Open concerns / deferred decisions

- **Traefik TLS passthrough vs re-encrypt**: passthrough needs `IngressRouteTCP`; re-encrypt uses normal `IngressRoute` with `serversTransport` to trust Nexus cert. Decide during plan phase based on existing Traefik patterns in repo.
- **First-boot race**: Nexus reports ready before internal DB writable. Provisioning Job must retry on 5xx with backoff. Plan phase to implement.
- **CoreDNS Corefile location**: Confirm exact ConfigMap to patch. Likely under `cluster/apps/kube-system/` but may be managed differently in this repo.
- **Renovate pinning**: Sonatype chart + Nexus image both pinned to exact versions, labels `dep/minor` / `dep/major` per existing convention.

## Risk assessment

**Low.** Stateless cache (blob store regeneratable), no cluster-critical dependency, PVC-backed, no auth model changes to existing workloads, no cloudflared exposure. Worst case: Nexus is wiped and rebuilds from upstream. Explicitly kept off the bootstrap / Flux / kubelet critical path.
