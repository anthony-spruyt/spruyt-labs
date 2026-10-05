# xfg - Coder workspace for developing xfg

## Overview

Workspace for [anthony-spruyt/xfg](https://github.com/anthony-spruyt/xfg), the CLI that syncs files and settings across GitHub, Azure DevOps and GitLab repos. It is the `devcontainer` template plus the xfg repo as default and the `coder-workspace-env-xfg` Secret. It has no access to the cluster API.

## Operations

- **Integration tokens.** `AZURE_DEVOPS_EXT_PAT` and `GITLAB_TOKEN` are set so xfg can be run and integration-tested against Azure DevOps and GitLab. Any repo opened in this template gets them too; use `devcontainer` for anything that isn't xfg.
- **SSH repo URL is enforced.** Pushes and commit signing use the bot SSH key, which HTTPS remotes never call.
- **gh and git.** You work as `spruyt-labs-bot`, the same identity as the write-tier Claude agents; in repos that require PR approval, approve its PRs with your own account. `gh` uses the write-tier GitHub App token (rotated every 30 minutes, symlinked at `~/.config/gh/hosts.yml`; do not `gh auth login`). Commits are signed with the bot SSH key, rotated daily; run `git-allowed-signers` if
  `git verify-commit` says `No principal matched`.
- **Persistence:** `/workspaces`, `/home/vscode` and podman storage survive restarts. Everything else is rebuilt from the repo's devcontainer on each start.
- **Containers:** rootful podman works inside the workspace. Pulls from docker.io, ghcr.io, quay.io, mcr.microsoft.com and registry.k8s.io go through the Nexus mirror automatically.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.
- **Terminals survive VS Code closing.** VS Code terminals (desktop and Web) open inside tmux through `~/.local/bin/tmux-term`. Closing VS Code leaves the tmux session running, and the next terminal you open rejoins a detached one. VS Code binds `Ctrl+B` to the sidebar, so the tmux prefix key doesn't reach tmux; mouse mode is on for scrolling and pane focus.
- **Phone and browser control with [Happy](https://github.com/slopus/happy).** Run `happy` in place of `claude`. Workspaces start paired when the `coder-happy-xfg` secret holds a template key ([#3339](https://github.com/anthony-spruyt/spruyt-labs/issues/3339)), and `happy auth logout` then lasts only until the next start; otherwise the first run shows a QR code to scan in the Happy app. `~/.happy`
  is on the home volume, so pairing survives restarts, and once paired, each workspace start runs the Happy daemon (so the app can open new sessions) and a `happy` session in the workspace folder. Attach to it with `tmux -L happy attach -t happy`; it is left alone if already running. Sessions use the same LiteLLM env as `claude`. Traffic relays through the self-hosted
  [Happy server](https://github.com/anthony-spruyt/spruyt-labs/blob/main/cluster/apps/happy-system/happy-server/README.md), end-to-end encrypted ([#3305](https://github.com/anthony-spruyt/spruyt-labs/issues/3305)). A paired device can run Claude and shell commands with this workspace's credentials, so unpair lost phones from the Happy app.

## Troubleshooting

1. **Workspace starts without your tools**
   - **Cause**: The devcontainer build failed, so the `Fallback image` parameter was started instead.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart.
