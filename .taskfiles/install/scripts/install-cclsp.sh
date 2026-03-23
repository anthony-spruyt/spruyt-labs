#!/bin/bash
set -euo pipefail

# renovate: depName=cclsp datasource=npm
VERSION="0.7.0"

echo "Installing cclsp ${VERSION}..."
npm install -g "cclsp@${VERSION}"

echo "✅ cclsp ${VERSION} installed successfully."
