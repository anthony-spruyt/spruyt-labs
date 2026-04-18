#!/bin/bash
set -euo pipefail

# renovate: depName=kubernetes/kubernetes datasource=github-releases
VERSION="v1.35.4"

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
if [[ -f /usr/local/bin/kubectl ]]; then
  sudo rm -f /usr/local/bin/kubectl
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -Lo "$TMPDIR/kubectl" "https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl"
sudo install -o root -g root -m 0755 "$TMPDIR/kubectl" /usr/local/bin/kubectl

echo "✅ kubectl ${VERSION} installed successfully."
