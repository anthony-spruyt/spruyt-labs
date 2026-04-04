# Coder Devcontainer Template

Kubernetes workspace template for Coder that builds from `devcontainer.json`.

## Usage

Push to Coder:

    coder templates push devcontainer --directory .

## Features

- Builds from any repo's `.devcontainer/devcontainer.json`
- Docker-in-Docker for MegaLinter and container builds
- cluster-admin ServiceAccount for kubectl/helm/flux
- SSH signing key for verified git commits
- GitHub App token for git clone/push (rotated hourly)
- Talosconfig and Terraform credentials mounted

## Secrets Required

The following Kubernetes Secrets must exist in `coder-system`:

- `coder-secrets` — SSH signing key, talosconfig, terraform creds, API keys
- `coder-ssh-signing-key` — SSH ed25519 key pair (managed by ssh-key-rotation CronJob)
- `github-bot-credentials` — GitHub App installation token (managed by github-system)
