#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# --- Ensure flux is installed ---
if ! command -v flux &> /dev/null; then
  echo "🔧 Flux not found. Installing Flux CLI..."
  curl -s https://fluxcd.io/install.sh | sudo bash
else
  echo "✅ Flux CLI is already installed."
fi

echo "🚀 Checking Flux version..."
flux --version

echo "✅ Flux CLI"
