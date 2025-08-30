#!/bin/bash
set -euo pipefail

chmod u+x **/*.sh

curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin

echo "🔧 Running dev env setup tasks..."
task dev-env:install-talhelper
task dev-env:install-helm-plugins
task dev-env:install-flux
task dev-env:install-flux-capacitor
task dev-env:install-age
task pre-commit:init
task terraform:init
