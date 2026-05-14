#!/bin/bash
set -euo pipefail

# renovate: depName=budimanjojo/talhelper datasource=github-releases
VERSION="v3.1.10"

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
if [[ -f /usr/local/bin/talhelper ]]; then
  sudo rm -f /usr/local/bin/talhelper
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="talhelper_linux_${ARCH}.tar.gz"
curl -Lo "$TMPDIR/$TARBALL" "https://github.com/budimanjojo/talhelper/releases/download/${VERSION}/${TARBALL}"
curl -Lo "$TMPDIR/checksums.txt" "https://github.com/budimanjojo/talhelper/releases/download/${VERSION}/checksums.txt"
(cd "$TMPDIR" && grep "$TARBALL" checksums.txt | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/talhelper" /usr/local/bin/talhelper
sudo chmod +x /usr/local/bin/talhelper

echo "✅ talhelper CLI ${VERSION} installed successfully."
