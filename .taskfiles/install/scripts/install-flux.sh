#!/bin/bash
set -euo pipefail

curl -s https://fluxcd.io/install.sh | sudo bash

# ✅ Verify installation
if command -v flux &>/dev/null; then
  echo "✅ Flux is ready: $(flux --version)"
else
  echo "❌ Flux installation failed. Please check the install script or install manually:"
  echo "👉 https://fluxcd.io/flux/installation/"
  exit 1
fi
