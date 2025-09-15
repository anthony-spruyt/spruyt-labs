#!/bin/bash
set -euo pipefail

# Define architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Fetch latest Velero release tag from GitHub
LATEST_TAG=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest | grep '"tag_name":' | cut -d '"' -f4)

# Construct download URL
TARBALL="velero-${LATEST_TAG}-linux-${ARCH}.tar.gz"
URL="https://github.com/vmware-tanzu/velero/releases/download/${LATEST_TAG}/${TARBALL}"

# Download and extract
curl -LO "$URL"
tar -xvf "$TARBALL"

# Move binary to /usr/local/bin
sudo mv "velero-${LATEST_TAG}-linux-${ARCH}/velero" /usr/local/bin/velero
sudo chmod +x /usr/local/bin/velero

# Clean up
rm -rf "$TARBALL" "velero-${LATEST_TAG}-linux-${ARCH}"

echo "✅ Velero CLI ${LATEST_TAG} installed successfully."
