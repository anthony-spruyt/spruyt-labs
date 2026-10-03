#!/bin/bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="$(yq -e '.instance.distribution.version' "${REPO_ROOT}/cluster/apps/flux-system/flux-instance/app/values.yaml")"
skip_if_installed flux "${VERSION}" "$(flux --version 2>/dev/null | awk '{print $3}')"

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

TARBALL="flux_${VERSION}_linux_${ARCH}.tar.gz"
CHECKSUMS="flux_${VERSION}_checksums.txt"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/fluxcd/flux2/releases/download/v${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$CHECKSUMS" "https://github.com/fluxcd/flux2/releases/download/v${VERSION}/${CHECKSUMS}"
(cd "$TMPDIR" && grep "  ${TARBALL}$" "$CHECKSUMS" | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo install -o root -g root -m 0755 "$TMPDIR/flux" /usr/local/bin/flux

echo "✅ Flux CLI ${VERSION} installed successfully."
