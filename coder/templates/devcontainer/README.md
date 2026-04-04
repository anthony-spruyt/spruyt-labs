# Coder Devcontainer Template

Kubernetes workspace template for Coder that builds from `devcontainer.json`.

## Usage

Push to Coder:

    coder templates push devcontainer --directory .

## Features

- Builds from any repo's `.devcontainer/devcontainer.json`
- Docker-in-Docker for MegaLinter and container builds
- cluster-admin ServiceAccount for kubectl/helm/flux
- SSH key for git auth and verified commit signing
- Talosconfig and Terraform credentials mounted

## Secrets Required

The following Kubernetes Secrets must exist in `coder-system`:

- `coder-ssh-signing-key` — SSH key for git auth + commit signing (rotated weekly by CronJob)
- `coder-talosconfig` — Talos client config mounted at `~/.talos/config`
- `coder-terraform-credentials` — Terraform credentials at `~/.terraform.d/credentials.tfrc.json`
- `coder-workspace-env` — Env vars injected into pods (e.g., `CLAUDE_CODE_OAUTH_TOKEN`)
