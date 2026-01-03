# Development Environment

This repository uses a VS Code devcontainer for a consistent development experience.

## Prerequisites

- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine
- SSH agent running with keys loaded (see [SSH Agent Setup](#ssh-agent-setup))

## Host Directory Structure

The devcontainer expects these directories on your host machine:

```text
~/.secrets/
├── .env                    # Environment variables (loaded via --env-file)
├── .terraform.d/           # Terraform credentials and plugin cache
├── age.key                 # SOPS Age private key
├── kubeconfig              # Kubernetes cluster config
├── talosconfig             # Talos cluster config
└── ...                     # Other secrets as needed

~/.claude/                  # Claude Code settings and memory
```

Create the required structure:

```bash
mkdir -p ~/.secrets/.terraform.d ~/.claude
touch ~/.secrets/.env
```

The `.env` file sets environment variables and paths to secrets:

```bash
GH_TOKEN=<github-token>
CONTEXT7_API_KEY=<context7-key>
SOPS_AGE_KEY_FILE=/home/vscode/.secrets/age.key
KUBECONFIG=/home/vscode/.secrets/kubeconfig
TALOSCONFIG=/home/vscode/.secrets/talosconfig
```

## SSH Agent Setup

The devcontainer uses SSH agent forwarding via socket mount. Your private keys stay on
the host and are never copied into the container.

**Requirements:**

- SSH agent running with your key loaded
- `SSH_AUTH_SOCK` environment variable set and exported

**Linux/WSL:**

```bash
# Start agent and add key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Verify SSH_AUTH_SOCK is set
echo $SSH_AUTH_SOCK
```

For passphrase-protected keys, use `keychain` to persist across sessions:

```bash
# Install: sudo apt install keychain
# Add to ~/.bashrc or ~/.zshrc:
eval "$(keychain --eval --agents ssh id_ed25519)"
```

`keychain` prompts for your passphrase once per reboot and reuses the agent across terminals.

**macOS:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Keys added with `--apple-use-keychain` persist across restarts. The `SSH_AUTH_SOCK` is
set automatically by macOS.

**Windows (Git Bash):**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Or enable the OpenSSH Authentication Agent service in Windows Services and ensure
`SSH_AUTH_SOCK` is set in your environment.

## Opening the Devcontainer

1. Ensure SSH agent is running and `SSH_AUTH_SOCK` is set
2. Clone the repository
3. Open the folder in VS Code
4. When prompted, click "Reopen in Container" (or run `Dev Containers: Reopen in Container` from the command palette)

The container uses Docker-in-Docker for running containers (MegaLinter, etc.) without
mounting the host Docker socket.
