#!/bin/bash
set -euo pipefail

# renovate: depName=golang/tools datasource=go packageName=golang.org/x/tools/gopls
VERSION="v0.21.1"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed gopls "${VERSION}" "$(gopls version 2>/dev/null | awk '{print $2}')"

echo "Installing gopls ${VERSION}..."
go install "golang.org/x/tools/gopls@${VERSION}"

echo "✅ gopls ${VERSION} installed successfully."
