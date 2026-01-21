#!/bin/bash
set -euo pipefail

# renovate: depName=falcosecurity/falcoctl datasource=github-releases
VERSION="v0.12.0"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Remove existing to ensure version update
if [[ -f /usr/local/bin/falcoctl ]]; then
  sudo rm -f /usr/local/bin/falcoctl
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Version without 'v' prefix for download URL
VERSION_NUM="${VERSION#v}"
TARBALL="falcoctl_${VERSION_NUM}_linux_${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/falcosecurity/falcoctl/releases/download/${VERSION}/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/falcoctl" /usr/local/bin/falcoctl
sudo chmod +x /usr/local/bin/falcoctl

echo "✅ falcoctl CLI ${VERSION} installed successfully."
