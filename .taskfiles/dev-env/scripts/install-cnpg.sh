#!/bin/bash
set -euo pipefail

# Define architecture (CNPG uses x86_64/arm64 not amd64)
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Fetch latest CNPG release tag from GitHub (e.g., v1.28.0)
LATEST_TAG=$(curl -s https://api.github.com/repos/cloudnative-pg/cloudnative-pg/releases/latest | grep '"tag_name":' | cut -d '"' -f4)
# Strip 'v' prefix for filename (v1.28.0 -> 1.28.0)
VERSION="${LATEST_TAG#v}"

# Construct download URL
TARBALL="kubectl-cnpg_${VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/cloudnative-pg/cloudnative-pg/releases/download/${LATEST_TAG}/${TARBALL}"

# Create temp directory
TMPDIR=$(mktemp -d)
cd "$TMPDIR"

# Download and extract
curl -sLO "$URL"
tar -xzf "$TARBALL"

# Move binary to /usr/local/bin
sudo mv kubectl-cnpg /usr/local/bin/kubectl-cnpg
sudo chmod +x /usr/local/bin/kubectl-cnpg

# Clean up
cd - > /dev/null
rm -rf "$TMPDIR"

echo "✅ CNPG kubectl plugin ${LATEST_TAG} installed successfully."
