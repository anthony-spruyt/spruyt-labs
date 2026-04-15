#!/bin/bash
set -euo pipefail

# Repo-specific devcontainer setup.
# Called by post-create.sh after safe-chain, pre-commit, and claude-cli are installed.

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
