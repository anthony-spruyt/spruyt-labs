# devcontainer - Workspace for any repo with a devcontainer

## Overview

Builds a workspace from any repository's `.devcontainer/devcontainer.json`. It has no access to the cluster API and no project credentials; use `spruyt-labs` for homelab ops and `xfg` for xfg.

## Prerequisites

The repository needs:

- An SSH URL (`git@` or `ssh://`). HTTPS is rejected at create time: pushes and commit signing use the workspace SSH key, which HTTPS remotes never call.
- A `vscode` remote user (UID 1000) with passwordless `sudo`. Home is mounted at `/home/vscode`, and startup uses `sudo` to mount the container disk. Without it startup stops before commit signing is configured.
- `jq` in the image, if you want `customizations.vscode.extensions` installed into VS Code Web.
- For apt through the Nexus cache: `"build": { "args": { "NEXUS_URL": "${localEnv:NEXUS_URL}" } }` in `devcontainer.json`, plus `ARG NEXUS_URL` and a `sources.list` rewrite in the Dockerfile. Copy the [spruyt-labs Dockerfile](https://github.com/anthony-spruyt/spruyt-labs/blob/main/.devcontainer/Dockerfile). Without it apt goes to the internet directly.

## What to expect

- **Persistence:** `/workspaces`, `/home/vscode` and podman storage (`/var/lib/containers`) survive restarts. Everything else is rebuilt from the devcontainer on each start.
- **Containers:** rootful podman works inside the workspace. Pulls from docker.io, ghcr.io, quay.io, mcr.microsoft.com and registry.k8s.io go through the Nexus mirror automatically.
- **Git signing key rotates:** the SSH key is replaced every 2 days and reaches a running workspace within a couple of minutes. Old keys stay valid on GitHub for 8 days.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.

## Troubleshooting

1. **Workspace starts without your tools**
   - **Cause**: The devcontainer build failed, so the `Fallback image` parameter was started instead.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart.
