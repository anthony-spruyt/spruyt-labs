#!/bin/bash
set -euo pipefail

sudo find . -type f -name '*.sh' -exec chmod u+x {} +

curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin

echo "🔧 Running dev env setup tasks..."

task dev-env:install-safe-chain
task dev-env:install-talosctl
task dev-env:install-talhelper
task dev-env:install-helm-plugins
task dev-env:install-flux
task dev-env:install-flux-capacitor
task dev-env:install-age
task dev-env:install-velero
task dev-env:install-hubble
task pre-commit:init

# Configure Claude Code MCP with Context7 for documentation lookup
if command -v claude &> /dev/null && [ -f ".kilocode/mcp.json" ]; then
    CONTEXT7_KEY=$(jq -r '.mcpServers.context7.headers.CONTEXT7_API_KEY' .kilocode/mcp.json)
    claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp \
        --header "CONTEXT7_API_KEY: ${CONTEXT7_KEY}" 2>/dev/null || true
fi
