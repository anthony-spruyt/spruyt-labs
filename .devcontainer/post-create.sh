#!/bin/bash
set -euo pipefail

sudo find . -type f -name '*.sh' -exec chmod u+x {} +

curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin

echo "🔧 Running dev env setup tasks..."
task dev-env:install-talhelper
task dev-env:install-helm-plugins
task dev-env:install-flux
task dev-env:install-flux-capacitor
task dev-env:install-age
task dev-env:install-velero
task pre-commit:init
