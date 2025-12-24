#!/bin/bash
set -euo pipefail

sudo find . -type f -name '*.sh' -exec chmod u+x {} +

curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin

echo "🔧 Running dev env setup tasks..."

# IMPORTANT: safe-chain MUST be first - it secures npm before any node-based installs
task dev-env:install-safe-chain

task dev-env:install-kubectl
task dev-env:install-kustomize
task dev-env:install-helm
task dev-env:install-helmfile
task dev-env:install-helm-plugins
task dev-env:install-cilium
task dev-env:install-hubble
task dev-env:install-talosctl
task dev-env:install-talhelper
task dev-env:install-flux
task dev-env:install-flux-capacitor
task dev-env:install-age
task dev-env:install-velero
task dev-env:install-cnpg
task dev-env:install-claude-code
task pre-commit:init
