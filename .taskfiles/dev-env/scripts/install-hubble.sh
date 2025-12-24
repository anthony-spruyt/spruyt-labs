#!/bin/bash
set -euo pipefail

# renovate: depName=cilium/hubble datasource=github-releases
VERSION="v1.18.3"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Remove existing to ensure version update
if [[ -f /usr/local/bin/hubble ]]; then
  sudo rm -f /usr/local/bin/hubble
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="hubble-linux-${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/cilium/hubble/releases/download/${VERSION}/${TARBALL}"
curl -Lo "$TMPDIR/${TARBALL}.sha256sum" "https://github.com/cilium/hubble/releases/download/${VERSION}/${TARBALL}.sha256sum"
(cd "$TMPDIR" && sha256sum --check "${TARBALL}.sha256sum")
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/hubble" /usr/local/bin/hubble
sudo chmod +x /usr/local/bin/hubble

echo "✅ Hubble CLI ${VERSION} installed successfully."
