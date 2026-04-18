#!/usr/bin/env bash
set -euo pipefail

# renovate: depName=containers/common datasource=github-releases
PODMAN_SECCOMP_VERSION="v0.64.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/podman-seccomp.json"
URL="https://raw.githubusercontent.com/containers/common/${PODMAN_SECCOMP_VERSION}/pkg/seccomp/seccomp.json"

curl -fsSL "$URL" -o "$TARGET"
echo "Refreshed $TARGET from $URL"
