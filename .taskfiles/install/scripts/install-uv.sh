#!/bin/bash
set -euo pipefail

# renovate: depName=astral-sh/uv datasource=github-releases
VERSION="0.12.9"

ARCH=$(uname -m)
case "$ARCH" in
x86_64) ARCH="x86_64" ;;
aarch64) ARCH="aarch64" ;;
*)
  echo "Unsupported architecture: $ARCH"
  exit 1
  ;;
esac

# Remove existing to ensure version update
if [[ -f /usr/local/bin/uv ]]; then
  sudo rm -f /usr/local/bin/uv /usr/local/bin/uvx
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="uv-${ARCH}-unknown-linux-gnu.tar.gz"
CHECKSUM="${TARBALL}.sha256"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/astral-sh/uv/releases/download/${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$CHECKSUM" "https://github.com/astral-sh/uv/releases/download/${VERSION}/${CHECKSUM}"
(cd "$TMPDIR" && sha256sum --check "$CHECKSUM")
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/uv-${ARCH}-unknown-linux-gnu/uv" /usr/local/bin/uv
sudo mv "$TMPDIR/uv-${ARCH}-unknown-linux-gnu/uvx" /usr/local/bin/uvx
sudo chmod +x /usr/local/bin/uv /usr/local/bin/uvx

echo "✅ uv ${VERSION} installed successfully."
