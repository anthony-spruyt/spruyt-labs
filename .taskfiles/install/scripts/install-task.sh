#!/bin/bash
set -euo pipefail

# renovate: depName=go-task/task datasource=github-releases
VERSION="v3.54.0"

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
skip_if_installed task "${VERSION}" "$(task --version 2>/dev/null)"

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

TARBALL="task_linux_${ARCH}.tar.gz"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/$TARBALL" "https://github.com/go-task/task/releases/download/${VERSION}/${TARBALL}"
curl --proto '=https' --tlsv1.2 -Lo "$TMPDIR/task_checksums.txt" "https://github.com/go-task/task/releases/download/${VERSION}/task_checksums.txt"
(cd "$TMPDIR" && grep "  ${TARBALL}$" task_checksums.txt | sha256sum --check)
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
sudo install -o root -g root -m 0755 "$TMPDIR/task" /usr/local/bin/task

echo "✅ Task ${VERSION} installed successfully."
