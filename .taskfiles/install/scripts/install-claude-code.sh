#!/bin/bash
set -euo pipefail

echo "Installing Claude Code CLI..."
curl -fsSL https://claude.ai/install.sh | bash

# Verify installation
if command -v claude &> /dev/null; then
  echo "✅ Claude Code CLI installed successfully."
else
  echo "❌ Claude Code CLI installation failed."
  exit 1
fi
