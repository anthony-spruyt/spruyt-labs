#!/bin/bash
set -euo pipefail

# renovate: depName=helmfile/vals datasource=github-releases
VERSION="v0.47.0"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed vals "${VERSION}" "$(vals version 2>/dev/null | awk '/^Version:/{print $2}')"

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
if [[ -f /usr/local/bin/vals ]]; then
  sudo rm -f /usr/local/bin/vals
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="vals_${VERSION#v}_linux_${ARCH}.tar.gz"
CHECKSUMS="vals_${VERSION#v}_checksums.txt"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/helmfile/vals/releases/download/${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$CHECKSUMS" "https://github.com/helmfile/vals/releases/download/${VERSION}/${CHECKSUMS}"
(cd "$TMPDIR" && grep "$TARBALL" "$CHECKSUMS" | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo mv "$TMPDIR/vals" /usr/local/bin/vals
sudo chmod +x /usr/local/bin/vals

echo "✅ vals CLI ${VERSION} installed successfully."
