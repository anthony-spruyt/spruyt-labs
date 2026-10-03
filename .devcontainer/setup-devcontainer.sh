#!/bin/bash
set -euo pipefail

# Repo-specific devcontainer setup.
# Called by post-create.sh after safe-chain, pre-commit, and claude-cli are installed.

bash "$(dirname "${BASH_SOURCE[0]}")/../.taskfiles/install/scripts/install-task.sh"

echo "Installing repo-specific tools via taskfile..."

task install:kubectl-cli
task install:kustomize-cli
task install:helm-cli
task install:helmfile-cli
task install:helm-plugins
task install:cilium-cli
task install:hubble-cli
task install:talosctl-cli
task install:topf-cli
task install:uv-cli
task install:vals-cli
task install:flux-cli
task install:age-cli
task install:velero-cli
task install:cnpg-plugin
task install:falcoctl-cli
task install:gopls
task install:cclsp
task install:coder-cli
