#!/bin/bash
set -euo pipefail

# --- Ensure helm is installed ---
if ! command -v helm &> /dev/null; then
  echo "🔧 Helm not found. Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
  echo "✅ Helm is already installed."
fi