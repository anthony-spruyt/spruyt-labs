#!/bin/bash
set -euo pipefail

# renovate: depName=cilium/cilium-cli datasource=github-releases
VERSION="v0.20.1"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed cilium "${VERSION}" "$(cilium version --client 2>/dev/null | awk '/^cilium-cli:/{print $2}')"

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
if [[ -f /usr/local/bin/cilium ]]; then
  sudo rm -f /usr/local/bin/cilium
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="cilium-linux-${ARCH}.tar.gz"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/cilium/cilium-cli/releases/download/${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/${TARBALL}.sha256sum" "https://github.com/cilium/cilium-cli/releases/download/${VERSION}/${TARBALL}.sha256sum"
(cd "$TMPDIR" && sha256sum --check "${TARBALL}.sha256sum")
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/cilium" /usr/local/bin/cilium
sudo chmod +x /usr/local/bin/cilium

echo "✅ cilium CLI ${VERSION} installed successfully."
