# spruyt-labs - Homelab operations workspace

## Overview

Workspace for working on the spruyt-labs repo against the live cluster. Unlike `devcontainer` and `xfg`, it carries operator credentials, so `kubectl`, `flux`, `helm`, `talosctl`, `terraform` and `sops` work out of the box.

- **kubectl/flux/helm:** a kubeconfig is generated at startup for the `coder-workspace-ops` ServiceAccount. That account is a scoped-down cluster-admin: it cannot read Secrets or change RBAC, webhooks or CRDs.
- **talosctl:** `TALOSCONFIG` points at a Talos-issued `os:operator` config with a short-lived cert ([#3188](https://github.com/anthony-spruyt/spruyt-labs/issues/3188)). Logs, dmesg, services, health, etcd status/snapshot and reboot work. Upgrades, `apply-config` and reading machine config do not; run those from the host devcontainer.
- **terraform:** credentials are copied to `~/.terraform.d/credentials.tfrc.json` at startup.
- **sops:** `SOPS_AGE_KEY_FILE` points at the cluster's age key, which decrypts every SOPS file in the repo.

## Operations

- **Point it only at trusted repos.** The `Repository URL` parameter is editable, but whatever repo it builds runs with the credentials above.
- **SSH repo URL is enforced.** Git auth uses the workspace SSH key through `GIT_SSH_COMMAND`. HTTPS remotes never call it, so clone works anonymously but the first push fails with `Permission denied (publickey)` ([#984](https://github.com/anthony-spruyt/spruyt-labs/issues/984)).
- **Git signing key rotates.** The SSH key is replaced every 2 days and old keys stay valid on GitHub for 8. If push or signing starts failing with `publickey` errors on a long-running workspace, restart it.
- **Apt through Nexus needs repo support.** The template only sets `NEXUS_URL`. The repo's [devcontainer.json](https://github.com/anthony-spruyt/spruyt-labs/blob/main/.devcontainer/devcontainer.json) passes it as a build arg and its [Dockerfile](https://github.com/anthony-spruyt/spruyt-labs/blob/main/.devcontainer/Dockerfile) rewrites `sources.list`. Drop either and apt goes direct to Ubuntu.
- **Persistence:** `/workspaces`, `/home/vscode` and podman storage survive restarts. Everything else is rebuilt from the devcontainer on each start.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.

## Troubleshooting

1. **Workspace starts without your tools**
   - **Cause**: The devcontainer build failed, so the `Fallback image` parameter was started instead.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart.

Cluster-side design (Kata isolation, Nexus routing, RBAC): [Coder README](https://github.com/anthony-spruyt/spruyt-labs/blob/main/cluster/apps/coder-system/coder/README.md).
