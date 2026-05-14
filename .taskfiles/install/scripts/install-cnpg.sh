#!/bin/bash
set -euo pipefail

# renovate: depName=cloudnative-pg/cloudnative-pg datasource=github-releases
VERSION="v1.29.1"

ARCH=$(uname -m)
case "$ARCH" in
x86_64) ARCH="x86_64" ;;
aarch64) ARCH="arm64" ;;
*)
  echo "Unsupported architecture: $ARCH"
  exit 1
  ;;
esac

# Remove existing to ensure version update
if [[ -f /usr/local/bin/kubectl-cnpg ]]; then
  sudo rm -f /usr/local/bin/kubectl-cnpg
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# CNPG strips the 'v' prefix in filenames
FILE_VERSION="${VERSION#v}"
TARBALL="kubectl-cnpg_${FILE_VERSION}_linux_${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/${VERSION}/${TARBALL}"
curl -Lo "$TMPDIR/checksums.txt" "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/${VERSION}/cnpg-${FILE_VERSION}-checksums.txt"
(cd "$TMPDIR" && grep "${TARBALL}$" checksums.txt | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/kubectl-cnpg" /usr/local/bin/kubectl-cnpg
sudo chmod +x /usr/local/bin/kubectl-cnpg

echo "✅ CNPG kubectl plugin ${VERSION} installed successfully."
