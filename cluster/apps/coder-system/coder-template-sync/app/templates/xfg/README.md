# xfg - Coder workspace for developing xfg

## Overview

Workspace for [anthony-spruyt/xfg](https://github.com/anthony-spruyt/xfg), the CLI that syncs files and settings across GitHub, Azure DevOps and GitLab repos. It is the `devcontainer` template plus the xfg repo as default and the `coder-workspace-env-xfg` Secret. It has no access to the cluster API.

## Operations

- **Integration tokens.** `AZURE_DEVOPS_EXT_PAT` and `GITLAB_TOKEN` are set so xfg can be run and integration-tested against Azure DevOps and GitLab. Any repo opened in this template gets them too; use `devcontainer` for anything that isn't xfg.
- **SSH repo URL is enforced.** Pushes and commit signing use the workspace SSH key, which HTTPS remotes never call.
- **Git signing key rotates.** The SSH key is replaced every 2 days and old keys stay valid on GitHub for 8. If push or signing starts failing with `publickey` errors on a long-running workspace, restart it.
- **Persistence:** `/workspaces`, `/home/vscode` and podman storage survive restarts. Everything else is rebuilt from the repo's devcontainer on each start.
- **Containers:** rootful podman works inside the workspace. Pulls from docker.io, ghcr.io, quay.io, mcr.microsoft.com and registry.k8s.io go through the Nexus mirror automatically.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.

## Troubleshooting

1. **Workspace starts without your tools**
   - **Cause**: The devcontainer build failed, so the `Fallback image` parameter was started instead.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart.
