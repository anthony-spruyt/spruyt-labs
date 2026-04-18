# Coder spruyt-labs Template

Kubernetes workspace template for Coder, hardcoded to the `spruyt-labs` repo
(SSH URL enforced). Sibling of the generic `devcontainer` template; this one
pre-fills `coder_parameter.repo` and rejects HTTPS URLs at create time so
`git push` via the mounted signing key always works.

## Usage

Push to Coder:

    coder templates push spruyt-labs --directory .

## Features

- Defaults `repo` to `git@github.com:anthony-spruyt/spruyt-labs.git`
- Validation regex `^(git@|ssh://)` rejects HTTPS at create
- Builds from the repo's `.devcontainer/devcontainer.json`
- Docker-in-Docker for MegaLinter and container builds
- cluster-admin ServiceAccount for kubectl/helm/flux
- SSH key for git auth and verified commit signing
- Talosconfig and Terraform credentials mounted

## Nexus artifact proxy

Envbuilder pulls base + feature images via the in-cluster Nexus docker-group
connector (`nexus.nexus-system.svc.cluster.local:8082`) and pushes the kaniko
layer cache to the Nexus envbuilder-cache hosted repo (`:8083`). Driven by
`KANIKO_REGISTRY_MIRROR`, `ENVBUILDER_INSECURE`, and `ENVBUILDER_CACHE_REPO`
envs set here and the `ENVBUILDER_DOCKER_CONFIG_BASE64` auth entry in the
`coder-workspace-env` Secret.

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
- `coder-talosconfig` — Talos client config mounted at `~/.talos/config`
- `coder-terraform-credentials` — Terraform credentials at `~/.terraform.d/credentials.tfrc.json`
- `coder-workspace-env` — Env vars injected into pods
