# Coder Devcontainer Template

Generic Kubernetes workspace template for Coder that builds from
`devcontainer.json`. No cluster-admin, no Talos/Terraform credentials —
intended for arbitrary repos. The `spruyt-labs` template is the
homelab-privileged sibling.

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

Runtime apt inside the workspace is NOT routed through Nexus by this template.
Consumer repos wanting apt caching should add the following to their
`.devcontainer/Dockerfile`:

    RUN echo 'Acquire::http::Proxy "http://nexus.nexus-system.svc.cluster.local:8081/repository/apt-ubuntu-proxy/";' \
        > /etc/apt/apt.conf.d/01proxy

For HTTPS-upstream apt features (cli.github, nodesource, hashicorp, launchpad),
point the relevant `sources.list.d/*.list` entry at the matching Nexus
passthrough repo under `/repository/apt-<name>/`.

## Secrets Required

The following Kubernetes Secrets must exist in `coder-workspaces`:

- `coder-ssh-signing-key` — SSH key for git auth + commit signing (rotated weekly by CronJob)
- `coder-workspace-env` — Env vars injected into pods (envbuilder mirror auth, etc.)
- `coder-workspace-mcp-api-keys` — MCP API keys synced from `traefik/traefik-mcp-api-keys` via ExternalSecret
