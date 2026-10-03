#!/bin/bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VERSION="$(yq -e '.talosVersion' "${REPO_ROOT}/talos/topf.yaml")"
skip_if_installed talosctl "${VERSION}" "$(talosctl version --client --short 2>/dev/null | awk '/^Talos /{print $2}')"

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

BINARY="talosctl-linux-${ARCH}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$BINARY" "https://github.com/siderolabs/talos/releases/download/${VERSION}/${BINARY}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/sha256sum.txt" "https://github.com/siderolabs/talos/releases/download/${VERSION}/sha256sum.txt"
(cd "$TMPDIR" && grep "  ${BINARY}$" sha256sum.txt | sha256sum --check)
sudo install -o root -g root -m 0755 "$TMPDIR/$BINARY" /usr/local/bin/talosctl

echo "✅ talosctl ${VERSION} installed successfully."
