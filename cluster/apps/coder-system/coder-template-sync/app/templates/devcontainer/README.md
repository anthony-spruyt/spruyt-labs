# Coder Devcontainer Template

Generic Kubernetes workspace template for Coder that builds from
`devcontainer.json`.

## Usage

Push to Coder:

    coder templates push devcontainer --directory .

## Features

- Builds from any repo's `.devcontainer/devcontainer.json`
- Podman-in-Kata for container builds (rootful, virtio-blk storage)
- `coder-workspace` ServiceAccount (no cluster role binding) with token automount disabled — no cluster API access
- SSH key for git auth and verified commit signing
- Nexus registries.conf drop-in for container pull mirroring

## Nexus artifact proxy

Envbuilder pulls base + feature images via the in-cluster Nexus docker-group
connector (`nexus.nexus-system.svc.cluster.local:8082`) and pushes the kaniko
layer cache to the Nexus envbuilder-cache hosted repo (`:8083`). Driven by
`KANIKO_REGISTRY_MIRROR`, `ENVBUILDER_INSECURE`, and `ENVBUILDER_CACHE_REPO`
envs set here and the `ENVBUILDER_DOCKER_CONFIG_BASE64` auth entry in the
`coder-workspace-env` Secret.

Runtime container pulls (podman, skopeo, buildah) inside the workspace are
also routed through Nexus via a `registries.conf` drop-in mounted from the
`coder-workspace-registries-conf` ConfigMap (docker.io, ghcr.io, quay.io,
mcr.microsoft.com, registry.k8s.io → `nexus:8082`).

Base-layer Ubuntu archive apt is routed through Nexus `apt-ubuntu-proxy`:
envbuilder injects `NEXUS_URL=http://nexus.nexus-system.svc.cluster.local:8081`
into the devcontainer build (via `envbuilder_env` + the consumer repo's
`devcontainer.json` `build.args.NEXUS_URL`), and the consumer Dockerfile
rewrites `/etc/apt/sources.list` to point at the proxy. Consumer repos
must add an `ARG NEXUS_URL` + sources.list rewrite to their Dockerfile —
see `spruyt-labs` repo `.devcontainer/Dockerfile` for the reference
pattern (Ref #988).

Devcontainer features that manage their own apt source lists (github-cli,
nodesource, hashicorp, launchpad PPAs) still fetch upstream direct — per-
feature apt source overrides are out of scope.

## Secrets Required

The following Kubernetes Secrets must exist in `coder-workspaces`:

- `coder-ssh-signing-key` — SSH key for git auth + commit signing (rotated weekly by CronJob)
- `coder-workspace-env` — Env vars injected into pods (envbuilder mirror auth, etc.)
- `coder-workspace-mcp-api-keys` — Generic MCP API keys (Brave Search, GitHub) synced from `traefik/traefik-mcp-api-keys` via ExternalSecret
