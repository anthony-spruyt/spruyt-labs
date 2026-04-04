#!/bin/bash
set -euo pipefail

curl -L https://coder.com/install.sh | sh

# ✅ Verify installation
if command -v coder &>/dev/null; then
  echo "✅ Coder CLI is ready: $(coder version)"
else
  echo "❌ Coder CLI installation failed. Please check the install script or install manually:"
  echo "👉 https://coder.com/docs/install"
  exit 1
fi
