#!/bin/bash
set -euo pipefail

# renovate: depName=postfinance/topf datasource=github-releases
VERSION="v0.6.0"

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
if [[ -f /usr/local/bin/topf ]]; then
  sudo rm -f /usr/local/bin/topf
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="topf_linux_${ARCH}.tar.gz"
# Checksum filename interpolates the version without the leading "v"
CHECKSUMS="topf_${VERSION#v}_checksums.txt"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/postfinance/topf/releases/download/${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$CHECKSUMS" "https://github.com/postfinance/topf/releases/download/${VERSION}/${CHECKSUMS}"
(cd "$TMPDIR" && grep "$TARBALL" "$CHECKSUMS" | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/topf" /usr/local/bin/topf
sudo chmod +x /usr/local/bin/topf

echo "✅ topf CLI ${VERSION} installed successfully."
