#!/bin/bash
set -euo pipefail

sudo find . -type f -name '*.sh' -exec chmod u+x {} +

curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin

echo "🔧 Running dev env setup tasks..."

# IMPORTANT: safe-chain MUST be first - it secures npm before any node-based installs
task install:safe-chain

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
task install:claude-code-cli
task pre-commit:init
