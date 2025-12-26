#!/bin/bash
set -euo pipefail

sudo find . -type f -name '*.sh' -exec chmod u+x {} +

curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin

echo "🔧 Running dev env setup tasks..."

# IMPORTANT: safe-chain MUST be first - it secures npm before any node-based installs
task install:safe-chain

task install:kubectl
task install:kustomize
task install:helm
task install:helmfile
task install:helm-plugins
task install:cilium
task install:hubble
task install:talosctl
task install:talhelper
task install:flux
task install:flux-capacitor
task install:age
task install:velero
task install:cnpg
task install:claude-code
task pre-commit:init
