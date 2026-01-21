#!/bin/bash
set -euo pipefail

# renovate: depName=@anthropic-ai/claude-code datasource=npm
VERSION="2.1.14"

# Install globally via npm (no sudo needed with nvm)
npm install -g "@anthropic-ai/claude-code@${VERSION}" --safe-chain-skip-minimum-package-age

# Verify installation
if command -v claude &> /dev/null; then
  echo "✅ Claude Code CLI ${VERSION} installed successfully."
else
  echo "❌ Claude Code CLI installation failed."
  exit 1
fi
