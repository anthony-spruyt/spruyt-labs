#!/bin/bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="$(yq -e '.spec.chart.spec.version' "${REPO_ROOT}/cluster/apps/coder-system/coder/app/release.yaml")"
skip_if_installed coder "${VERSION}" "$(coder version 2>/dev/null | awk '/^Coder /{print $2}' | cut -d+ -f1)"

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

TARBALL="coder_${VERSION}_linux_${ARCH}.tar.gz"
CHECKSUMS="coder_${VERSION}_checksums.txt"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/coder/coder/releases/download/v${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$CHECKSUMS" "https://github.com/coder/coder/releases/download/v${VERSION}/${CHECKSUMS}"
(cd "$TMPDIR" && grep "  ${TARBALL}$" "$CHECKSUMS" | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo install -o root -g root -m 0755 "$TMPDIR/coder" /usr/local/bin/coder

echo "✅ Coder CLI ${VERSION} installed successfully."
