#!/bin/bash
set -euo pipefail

# Define architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Fetch latest Hubble release tag from GitHub
LATEST_TAG=$(curl -s https://api.github.com/repos/cilium/hubble/releases/latest | grep '"tag_name":' | cut -d '"' -f4)

# Construct download URL
TARBALL="hubble-linux-${ARCH}.tar.gz"
URL="https://github.com/cilium/hubble/releases/download/${LATEST_TAG}/${TARBALL}"

# Download and extract
curl -L --fail --remote-name-all "$URL" "${URL}.sha256sum"
sha256sum --check "${TARBALL}.sha256sum"
tar -xzf "$TARBALL"

# Move binary to /usr/local/bin
sudo mv hubble /usr/local/bin/hubble
sudo chmod +x /usr/local/bin/hubble

# Clean up
rm -rf "$TARBALL" "${TARBALL}.sha256sum"

echo "✅ Hubble CLI ${LATEST_TAG} installed successfully."
