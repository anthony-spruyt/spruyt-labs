#!/bin/bash
set -euo pipefail

# renovate: depName=falcosecurity/falcoctl datasource=github-releases
VERSION="v0.14.2"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed falcoctl "${VERSION}" "$(falcoctl version 2>/dev/null | awk '/^Client Version:/{print $3}')"

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
if [[ -f /usr/local/bin/falcoctl ]]; then
  sudo rm -f /usr/local/bin/falcoctl
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Version without 'v' prefix for download URL
VERSION_NUM="${VERSION#v}"
TARBALL="falcoctl_${VERSION_NUM}_linux_${ARCH}.tar.gz"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/falcosecurity/falcoctl/releases/download/${VERSION}/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/falcoctl" /usr/local/bin/falcoctl
sudo chmod +x /usr/local/bin/falcoctl

echo "✅ falcoctl CLI ${VERSION} installed successfully."
