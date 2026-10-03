#!/bin/bash
set -euo pipefail

# renovate: depName=helm/helm datasource=github-releases
VERSION="v4.3.0"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed helm "${VERSION}" "$(helm version --template '{{.Version}}' 2>/dev/null)"

ARCH=$(uname -m)
case "$ARCH" in
x86_64) ARCH="amd64" ;;
aarch64) ARCH="arm64" ;;
*)
  echo "Unsupported architecture: $ARCH"
  exit 1
  ;;
esac

# Remove existing to ensure version update
if [[ -f /usr/local/bin/helm ]]; then
  sudo rm -f /usr/local/bin/helm
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="helm-${VERSION}-linux-${ARCH}.tar.gz"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://get.helm.sh/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/linux-${ARCH}/helm" /usr/local/bin/helm
sudo chmod +x /usr/local/bin/helm

echo "✅ Helm ${VERSION} installed successfully."
