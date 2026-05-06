# Development Environment

Two paths to a working dev environment — both produce identical toolchains.

| Path                                      | Use when                                                          |
| ----------------------------------------- | ----------------------------------------------------------------- |
| [Local devcontainer](#local-devcontainer) | You have Docker/Podman on your machine and prefer VS Code locally |
| [Coder workspace](#coder-workspace)       | Browser-based or remote VS Code Desktop — zero host setup         |

## Local Devcontainer

### Prerequisites

- [VS Code](https://code.visualstudio.com/) with [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine
- SSH agent with keys loaded (see [SSH Agent Setup](#ssh-agent-setup))
- Host directories (see below)

### Host Directory Structure

```text
~/.secrets/
├── .env              # Environment variables (GH_TOKEN, CONTEXT7_API_KEY, etc.)
├── .terraform.d/     # Terraform credentials and plugin cache
├── age.key           # SOPS Age private key
├── kubeconfig        # Kubernetes cluster config
└── talosconfig       # Talos cluster config

~/.claude/            # Claude Code settings and memory (persists across rebuilds)
```

Create the required structure:

```bash
mkdir -p ~/.secrets/.terraform.d ~/.claude
touch ~/.secrets/.env
chmod 700 ~/.secrets
chmod 600 ~/.secrets/.env
```

The `.env` file must contain:

```bash
GH_TOKEN=<github-token>
CONTEXT7_API_KEY=<context7-key>
SOPS_AGE_KEY_FILE=/home/vscode/.secrets/age.key
KUBECONFIG=/home/vscode/.secrets/kubeconfig
TALOSCONFIG=/home/vscode/.secrets/talosconfig
```

### SSH Agent Setup

The `initialize.sh` script runs on your host before container creation and creates a stable symlink at `~/.ssh/agent.sock`. This handles SSH agent forwarding automatically — the container mounts that fixed path.

**Linux/WSL** — requires `keychain`:

```bash
sudo apt install keychain
```

Add to `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(keychain --eval --agents ssh id_ed25519)"
```

**macOS:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Keys persist across restarts via Apple keychain.

### Opening the Devcontainer

1. Clone the repository
1. Open in VS Code
1. Click "Reopen in Container" (or Command Palette → `Dev Containers: Reopen in Container`)

`initialize.sh` sets up the SSH socket, then `devcontainer-post-create` installs tooling inside the container.

## Coder Workspace

Coder provides browser-based (or VS Code Desktop) workspaces running as Kubernetes pods. No host prerequisites beyond a browser.

### Creating a Workspace

1. Navigate to `https://code.${EXTERNAL_DOMAIN}`
1. Sign in via Authentik SSO
1. Create workspace from the **spruyt-labs** template
1. Configure parameters:
   - **Repository URL** — SSH URL (default: `git@github.com:anthony-spruyt/spruyt-labs.git`)
   - **Git commit email** — GitHub noreply address for verified commits
   - **Volume sizes** — `/workspaces` (default 20 GiB), `/home/vscode` (default 20 GiB)

### How It Works

The Coder template uses [envbuilder](https://github.com/coder/envbuilder) to build the same devcontainer image inside a [Kata Containers](https://katacontainers.io/) VM. This provides:

- **Same toolchain** as local devcontainer — identical base image, features, and setup scripts
- **Secrets via Kubernetes volumes** — SSH signing key, talosconfig, SOPS age key, Terraform credentials (no `~/.secrets/` needed)
- **Git commit signing** — automatic via mounted SSH key at `/etc/coder/ssh-keys/id_ed25519`
- **Nexus proxy** — apt and container pulls route through in-cluster Nexus for caching
- **OTel telemetry** — Claude Code traces/metrics/logs ship to VictoriaMetrics

### Accessing the Workspace

- **Browser**: VS Code Web via the Coder dashboard
- **VS Code Desktop**: Install Coder extension, connect to workspace
- **SSH**: `coder ssh <workspace-name>`
- **Terminal**: Web terminal available in dashboard

### Persistent Storage

| Mount                  | Storage Class             | Purpose                                 |
| ---------------------- | ------------------------- | --------------------------------------- |
| `/workspaces`          | `rbd-fast-delete`         | Repository checkout, build artifacts    |
| `/home/vscode`         | `rbd-fast-delete`         | User config, Claude memory, tool caches |
| `/dev/containers-disk` | `rbd-fast-delete` (block) | Podman container storage (ext4)         |

Volumes persist across workspace stop/start. Deleting the workspace deletes volumes.

## Common to Both Paths

### Base Image

Both paths use `ghcr.io/anthony-spruyt/devcontainer-common` which includes Python, Node, GitHub CLI, pre-commit, rootless Podman, and the `agent-run` policy wrapper.

### Devcontainer Features

Pinned versions installed as devcontainer features:

- Go
- Renovate CLI
- Terraform
- SOPS
- yq

### CLI Tools

Installed by `setup-devcontainer.sh` via Taskfile:

kubectl, kustomize, helm, helmfile, helm plugins, cilium, hubble, talosctl, talhelper, flux, flux-capacitor, age, velero, cnpg plugin, falcoctl, gopls, cclsp, coder

### Container Runtime

The devcontainer uses **rootless Podman** (via `podman-docker` shim). The `docker` command maps to `podman`. Container image pulls route through a registry allow-list — short-name pulls from unregistered registries are rejected.

For details on the security posture (seccomp, `agent-run` wrapper, registry enforcement), see [`.devcontainer/README.md`](.devcontainer/README.md).

### VS Code Extensions

Auto-installed in both local and Coder workspaces:

Claude Code, Markdown Mermaid, Better JSON5, Prettier, Git Graph, YAML, GitHub Actions, Go, Terraform, Task Runner, Helm Intellisense

## Troubleshooting

### SSH agent socket errors (local only)

**Error**: `error mounting "..." to rootfs at "/ssh-agent": not a directory`

**Cause**: SSH agent socket path changed (reboot), but container cached old path.

**Fix**: Ensure `keychain` is in `~/.bashrc`, run `source ~/.bashrc`, verify `ls -la ~/.ssh/agent.sock`, then rebuild container.

### Podman reports `vfs` storage driver

**Cause**: `/etc/containers/storage.conf` missing or graphroot populated by vfs.

**Fix**: `sudo rm -rf /var/lib/containers/storage` and rebuild devcontainer.

### Rootless `newuidmap: exit status 1` (WSL2)

**Cause**: Outer namespace lacks delegated subuid ranges.

**Fix**: Use `sudo podman`. MegaLinter's `lint.sh` handles this automatically.
