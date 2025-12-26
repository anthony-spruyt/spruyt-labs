#!/bin/bash
set -euo pipefail

# renovate: depName=vmware-tanzu/velero datasource=github-releases
VERSION="v1.17.1"

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Remove existing to ensure version update
if [[ -f /usr/local/bin/velero ]]; then
  sudo rm -f /usr/local/bin/velero
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="velero-${VERSION}-linux-${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/vmware-tanzu/velero/releases/download/${VERSION}/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/velero-${VERSION}-linux-${ARCH}/velero" /usr/local/bin/velero
sudo chmod +x /usr/local/bin/velero

echo "✅ Velero CLI ${VERSION} installed successfully."
