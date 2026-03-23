#!/bin/bash
set -euo pipefail

# renovate: depName=golang/tools datasource=go packageName=golang.org/x/tools/gopls
VERSION="v0.21.1"

echo "Installing gopls ${VERSION}..."
go install "golang.org/x/tools/gopls@${VERSION}"

echo "✅ gopls ${VERSION} installed successfully."
