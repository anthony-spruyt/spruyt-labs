#!/bin/bash
set -euo pipefail

# renovate: depName=FiloSottile/age datasource=github-releases
VERSION="v1.3.2"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed age "${VERSION}" "$(age --version 2>/dev/null)"

ARCH=$(uname -m)
case "$ARCH" in
x86_64) ARCH="amd64" ;;
aarch64) ARCH="arm64" ;;
*)
  echo "Unsupported architecture: $ARCH"
  exit 1
  ;;
esac

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# age publishes sigsum proofs, not checksums
TARBALL="age-${VERSION}-linux-${ARCH}.tar.gz"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/FiloSottile/age/releases/download/${VERSION}/${TARBALL}"
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo install -o root -g root -m 0755 "$TMPDIR/age/age" "$TMPDIR/age/age-keygen" /usr/local/bin/

echo "✅ age ${VERSION} installed successfully."
