# spruyt-labs - Homelab operations workspace

## Overview

Workspace for working on the spruyt-labs repo against the live cluster. Unlike `devcontainer` and `xfg`, it carries operator credentials, so `kubectl`, `flux`, `helm`, `talosctl`, `terraform`, `sops` and `coder` work out of the box.

- **kubectl/flux/helm:** a kubeconfig is generated at startup for the `coder-workspace-ops` ServiceAccount. That account is a scoped-down cluster-admin: it cannot read Secrets or change RBAC, webhooks or CRDs.
- **talosctl:** `TALOSCONFIG` points at a Talos-issued `os:operator` config with a short-lived cert ([#3188](https://github.com/anthony-spruyt/spruyt-labs/issues/3188)). Logs, dmesg, services, etcd status/snapshot and reboot work. `health`, upgrades, `apply-config` and reading machine config do not; run those from the host devcontainer. The config has no nodes, so a `talosctl` wrapper in
  `~/.local/bin` fills in `-n` from `kubectl get nodes` for read-only commands (`version`, `get`, `services`, `logs`, `dmesg` and similar; `etcd members/status` go to control planes only). Anything that changes a node, such as `reboot` or `services <id> restart`, still needs an explicit `-n`.
- **terraform:** `~/.terraform.d/credentials.tfrc.json` is a symlink to the mounted credentials.
- **coder:** `CODER_URL` and `CODER_SESSION_TOKEN` log the CLI in as the workspace owner, with the owner's full Coder rights ([#3346](https://github.com/anthony-spruyt/spruyt-labs/issues/3346)). Coder issues a new token on every start, so there is nothing to rotate. The token lasts only as long as your Authentik refresh token; if `coder` starts returning `401`, sign out of the Coder web UI and
  back in.
- **gh and git:** you work as `spruyt-labs-bot`, the same identity as the write-tier Claude agents. `~/.config/gh/hosts.yml` is a symlink to the write-tier GitHub App token, rotated every 30 minutes. Commits are signed with the bot's SSH key. `git verify-commit` checks against `~/.config/git/allowed_signers`, built at startup from the bot's GitHub signing keys; run `git-allowed-signers` to refresh
  it if a check says `No principal matched`. In repos that require PR approval, approve the bot's PRs with your own account.
- **sops:** `SOPS_AGE_KEY_FILE` points at the cluster's age key, which decrypts every SOPS file in the repo.

## Operations

- **Point it only at trusted repos.** The `Repository URL` parameter is editable, but whatever repo it builds runs with the credentials above.
- **SSH repo URL is enforced.** Git auth uses the bot SSH key through `GIT_SSH_COMMAND`. HTTPS remotes never call it, so clone works anonymously but the first push fails with `Permission denied (publickey)` ([#984](https://github.com/anthony-spruyt/spruyt-labs/issues/984)).
- **Credentials rotate in place.** The bot SSH key rotates daily and the GitHub token every 30 minutes. Both reach a running workspace within a couple of minutes, no restart needed ([#3189](https://github.com/anthony-spruyt/spruyt-labs/issues/3189)). Do not `gh auth login`: it replaces the symlink with a file that never rotates.
- **Apt through Nexus needs repo support.** The template only sets `NEXUS_URL`. The repo's [devcontainer.json](https://github.com/anthony-spruyt/spruyt-labs/blob/main/.devcontainer/devcontainer.json) passes it as a build arg and its [Dockerfile](https://github.com/anthony-spruyt/spruyt-labs/blob/main/.devcontainer/Dockerfile) rewrites `sources.list`. Drop either and apt goes direct to Ubuntu.
- **The base image comes from Nexus only.** The template sets `BASE_REGISTRY` to Nexus, and the Dockerfile's `FROM ${BASE_REGISTRY}/...` reads it. If Nexus is down, the build fails; there is no direct-registry fallback ([#3229](https://github.com/anthony-spruyt/spruyt-labs/issues/3229)).
- **Persistence:** `/workspaces`, `/home/vscode` and podman storage survive restarts. Everything else is rebuilt from the devcontainer on each start.
- **Claude Code:** starts in `bypassPermissions` mode from managed settings. Telemetry, including prompts and tool content, goes to the cluster's VictoriaMetrics/Logs/Traces.
- **Terminals survive VS Code closing.** VS Code terminals (desktop and Web) open inside tmux through `~/.local/bin/tmux-term`. Closing VS Code leaves the tmux session running, and the next terminal you open rejoins a detached one. VS Code binds `Ctrl+B` to the sidebar, so the tmux prefix key doesn't reach tmux; mouse mode is on for scrolling and pane focus.
- **Phone and browser control with [Happy](https://github.com/slopus/happy).** Run `happy` in place of `claude`. Workspaces start paired when the `coder-happy-spruyt-labs` secret holds a template key ([#3339](https://github.com/anthony-spruyt/spruyt-labs/issues/3339)), and `happy auth logout` then lasts only until the next start; otherwise the first run shows a QR code to scan in the Happy app.
  `~/.happy` is on the home volume, so pairing survives restarts, and once paired, each workspace start runs the Happy daemon (so the app can open new sessions; one opened in `~` starts in the workspace folder instead, [#3354](https://github.com/anthony-spruyt/spruyt-labs/issues/3354)) and, once the Happy server answers, a `happy` session in the workspace folder. Attach to it with
  `tmux -L happy attach -t happy`; it is left alone if already running. Sessions opened from the app have no terminal until [slopus/happy#1846](https://github.com/slopus/happy/pull/1846) ships, so a new terminal says when any are running, and `happy-here` moves one into it: it stops the daemon's copy, losing any reply still in progress, and reconnects the same session with its conversation
  ([#3358](https://github.com/anthony-spruyt/spruyt-labs/issues/3358)). The app lists the machine under the workspace name; one registered before [#3355](https://github.com/anthony-spruyt/spruyt-labs/issues/3355) keeps its `coder-<id>` name until renamed in the app. Sessions use the same LiteLLM env as `claude`. Traffic relays through the self-hosted
  [Happy server](https://github.com/anthony-spruyt/spruyt-labs/blob/main/cluster/apps/happy-system/happy-server/README.md), end-to-end encrypted ([#3305](https://github.com/anthony-spruyt/spruyt-labs/issues/3305)). A paired device can run Claude and shell commands with this workspace's credentials, so unpair lost phones from the Happy app.

## Troubleshooting

1. **Workspace starts without your tools**
   - **Cause**: The devcontainer build failed, so the `Fallback image` parameter was started instead.
   - **Fix**: Read the build output in the workspace logs, fix the devcontainer, then restart.

Cluster-side design (Kata isolation, Nexus routing, RBAC): [Coder README](https://github.com/anthony-spruyt/spruyt-labs/blob/main/cluster/apps/coder-system/coder/README.md).
