#!/bin/bash
set -euo pipefail

# Repo-specific devcontainer setup.
# Called by post-create.sh after safe-chain, pre-commit, and claude-cli are installed.

# --- Rootless Podman (replaces docker-in-docker) ---
# podman-docker provides /usr/bin/docker symlink → podman
# uidmap + slirp4netns enable rootless user namespaces and networking
# fuse-overlayfs is used when kernel overlayfs-on-userns is unavailable
echo "Installing rootless Podman..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  podman \
  podman-docker \
  fuse-overlayfs \
  uidmap \
  slirp4netns

# Confirm the vscode user has subuid/subgid allocations (required for rootless)
if ! grep -q '^vscode:' /etc/subuid; then
  echo "vscode:100000:65536" | sudo tee -a /etc/subuid >/dev/null
fi
if ! grep -q '^vscode:' /etc/subgid; then
  echo "vscode:100000:65536" | sudo tee -a /etc/subgid >/dev/null
fi

# Suppress the podman-docker "emulated" MOTD on every docker invocation
sudo mkdir -p /etc/containers
sudo touch /etc/containers/nodocker

# Install taskfile runner
curl -sSfL https://taskfile.dev/install.sh | sudo sh -s -- -b /usr/local/bin

echo "Installing repo-specific tools via taskfile..."

task install:kubectl-cli
task install:kustomize-cli
task install:helm-cli
task install:helmfile-cli
task install:helm-plugins
task install:cilium-cli
task install:hubble-cli
task install:talosctl-cli
task install:talhelper-cli
task install:flux-cli
task install:flux-capacitor
task install:age-cli
task install:velero-cli
task install:cnpg-plugin
task install:falcoctl-cli
task install:gopls
task install:cclsp
task install:coder-cli
