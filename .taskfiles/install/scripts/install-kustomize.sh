#!/bin/bash
set -euo pipefail

# renovate: depName=kubernetes-sigs/kustomize datasource=github-releases versioning=regex:^kustomize/v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
VERSION="v5.8.0"

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
if [[ -f /usr/local/bin/kustomize ]]; then
  sudo rm -f /usr/local/bin/kustomize
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="kustomize_${VERSION}_linux_${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${VERSION}/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/kustomize" /usr/local/bin/kustomize
sudo chmod +x /usr/local/bin/kustomize

echo "✅ kustomize ${VERSION} installed successfully."
