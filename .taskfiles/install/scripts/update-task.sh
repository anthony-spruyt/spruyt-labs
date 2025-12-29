#!/bin/bash
set -euo pipefail

echo "📦 Updating Task..."

# Get current version
CURRENT_VERSION=$(task --version 2>/dev/null | head -1 || echo "unknown")
echo "Current version: $CURRENT_VERSION"

# Install/update using official installer
curl -sSfL https://taskfile.dev/install.sh | sudo sh -s -- -b /usr/local/bin

# Show new version
NEW_VERSION=$(task --version 2>/dev/null | head -1)
echo "Updated to: $NEW_VERSION"
