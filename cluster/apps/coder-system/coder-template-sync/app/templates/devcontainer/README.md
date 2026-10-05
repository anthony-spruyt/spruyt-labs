# devcontainer - Workspace for any repo with a devcontainer

## Overview

Builds a workspace from any repository's `.devcontainer/devcontainer.json`. It has no access to the cluster API and no project credentials; use `spruyt-labs` for homelab ops and `xfg` for xfg.

## Prerequisites

The repository needs:

- An SSH URL (`git@` or `ssh://`). HTTPS is rejected at create time: pushes and commit signing use the bot SSH key, which HTTPS remotes never call.
- A `vscode` remote user (UID 1000) with passwordless `sudo`. Home is mounted at `/home/vscode`, and startup uses `sudo` to mount the container disk. Without it startup stops before commit signing is configured.
- `jq` and `curl` in the image, for `customizations.vscode.extensions` in VS Code Web and for `git verify-commit` (the startup step that builds `~/.config/git/allowed_signers`).
- For apt through the Nexus cache: `"build": { "args": { "NEXUS_URL": "${localEnv:NEXUS_URL}" } }` in `devcontainer.json`, plus `ARG NEXUS_URL` and a `sources.list` rewrite in the Dockerfile. Copy the [spruyt-labs Dockerfile](https://github.com/anthony-spruyt/spruyt-labs/blob/main/.devcontainer/Dockerfile). Without it apt goes to the internet directly.
- To pull the base image through Nexus: `ARG BASE_REGISTRY=docker.io` and `FROM ${BASE_REGISTRY}/...` in the Dockerfile, plus `"BASE_REGISTRY": "${localEnv:BASE_REGISTRY:docker.io}"` in `build.args`. envbuilder ignores registry mirrors, so without it the base image downloads straight from the registry.

## What to expect

- **Persistence:** `/workspaces`, `/home/vscode` and podman storage (`/var/lib/containers`) survive restarts. Everything else is rebuilt from the devcontainer on each start.
- **Containers:** rootful podman works inside the workspace. Pulls from docker.io, ghcr.io, quay.io, mcr.microsoft.com and registry.k8s.io go through the Nexus mirror automatically.
- **gh and git:** you work as `spruyt-labs-bot`, the same identity as the write-tier Claude agents; in repos that require PR approval, approve its PRs with your own account. `gh` uses the write-tier GitHub App token (rotated every 30 minutes, symlinked at `~/.config/gh/hosts.yml`; do not `gh auth login`). Commits are signed with the bot SSH key, rotated daily; run `git-allowed-signers` if
  `git verify-commit` says `No principal matched`.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.
- **Terminals survive VS Code closing.** VS Code terminals (desktop and Web) open inside tmux through `~/.local/bin/tmux-term`. Closing VS Code leaves the tmux session running, and the next terminal you open rejoins a detached one. VS Code binds `Ctrl+B` to the sidebar, so the tmux prefix key doesn't reach tmux; mouse mode is on for scrolling and pane focus.
- **Phone and browser control with [Happy](https://github.com/slopus/happy).** Run `happy` in place of `claude`. Workspaces start paired when the `coder-happy-devcontainer` secret holds a template key ([#3339](https://github.com/anthony-spruyt/spruyt-labs/issues/3339)), and `happy auth logout` then lasts only until the next start; otherwise the first run shows a QR code to scan in the Happy app.
  `~/.happy` is on the home volume, so pairing survives restarts, and once paired, each workspace start runs the Happy daemon (so the app can open new sessions; one opened in `~` starts in the workspace folder instead, [#3354](https://github.com/anthony-spruyt/spruyt-labs/issues/3354)) and, once the Happy server answers, a `happy` session in the workspace folder. Attach to it with
  `tmux -L happy attach -t happy`; it is left alone if already running. The app lists the machine under the workspace name; one registered before [#3355](https://github.com/anthony-spruyt/spruyt-labs/issues/3355) keeps its `coder-<id>` name until renamed in the app. Sessions use the same LiteLLM env as `claude`. Traffic relays through the self-hosted
  [Happy server](https://github.com/anthony-spruyt/spruyt-labs/blob/main/cluster/apps/happy-system/happy-server/README.md), end-to-end encrypted ([#3305](https://github.com/anthony-spruyt/spruyt-labs/issues/3305)). A paired device can run Claude and shell commands with this workspace's credentials, so unpair lost phones from the Happy app.

## Troubleshooting

1. **Workspace starts without your tools**
   - **Cause**: The devcontainer build failed, so the `Fallback image` parameter was started instead.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart.
