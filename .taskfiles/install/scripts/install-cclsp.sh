#!/bin/bash
set -euo pipefail

# renovate: depName=cclsp datasource=npm
VERSION="0.7.0"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed cclsp "${VERSION}" "$(npm ls -g --depth=0 cclsp 2>/dev/null | sed -n 's/.*cclsp@//p')"

echo "Installing cclsp ${VERSION}..."
npm install -g "cclsp@${VERSION}"

echo "✅ cclsp ${VERSION} installed successfully."
