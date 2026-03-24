#!/bin/bash
set -euo pipefail

# renovate: depName=helmfile/helmfile datasource=github-releases
VERSION="v1.4.3"

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
if [[ -f /usr/local/bin/helmfile ]]; then
  sudo rm -f /usr/local/bin/helmfile
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="helmfile_${VERSION#v}_linux_${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/helmfile/helmfile/releases/download/${VERSION}/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/helmfile" /usr/local/bin/helmfile
sudo chmod +x /usr/local/bin/helmfile

echo "✅ helmfile ${VERSION} installed successfully."
