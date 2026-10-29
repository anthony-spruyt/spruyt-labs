# xfg - Coder workspace for developing xfg

## Overview

Workspace for [anthony-spruyt/xfg](https://github.com/anthony-spruyt/xfg), the CLI that syncs files and settings across GitHub, Azure DevOps and GitLab repos. It is the `devcontainer` template plus the xfg repo as default and the `coder-workspace-env-xfg` Secret. It has no access to the cluster API.

## Operations

- **Integration tokens.** `AZURE_DEVOPS_EXT_PAT` and `GITLAB_TOKEN` are set so xfg can be run and integration-tested against Azure DevOps and GitLab. Use this template only for xfg; use `devcontainer` for other repos.
- **SSH repo URL is enforced.** Pushes and commit signing use the bot SSH key, which HTTPS remotes never call.
- **gh and git.** You work as `spruyt-labs-bot`, the same identity as the write-tier Claude agents; in repos that require PR approval, approve its PRs with your own account. `gh` uses the write-tier GitHub App token (rotated every 30 minutes, symlinked at `~/.config/gh/hosts.yml`; do not `gh auth login`). Commits are signed with the bot SSH key, rotated daily; run `git-allowed-signers` if
  `git verify-commit` says `No principal matched`.
- **Persistence:** `/workspaces`, `/home/vscode` and podman storage survive restarts. Everything else is rebuilt from the repo's devcontainer on each start.
- **Containers:** rootful podman works inside the workspace. Pulls from docker.io, ghcr.io, quay.io, mcr.microsoft.com and registry.k8s.io go through the Nexus mirror automatically.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.
- **Terminals survive VS Code closing.** VS Code terminals (desktop and Web) open inside tmux through `~/.local/bin/tmux-term`. Closing VS Code leaves the tmux session running, and the next terminal you open rejoins a detached one. VS Code binds `Ctrl+B` to the sidebar, so the tmux prefix key doesn't reach tmux; mouse mode is on for scrolling and pane focus.

## Troubleshooting

1. **Workspace fails to start after a build error**
   - **Cause**: The devcontainer build failed. The template sets no fallback image, so envbuilder exits with the build error rather than start an image without your tools.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart. An apt `Remote Auto Blocked` error means Nexus timed out on its upstream; wait a minute, then restart.
