#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"

echo "=== cluster-settings (cluster/flux/meta/cluster-settings.yaml) ==="
yq '.data | keys | .[]' "${ROOT_DIR}/cluster/flux/meta/cluster-settings.yaml"
echo ""
echo "=== cluster-secrets (cluster/flux/meta/cluster-secrets.sops.yaml) ==="
yq '.stringData | keys | .[]' "${ROOT_DIR}/cluster/flux/meta/cluster-secrets.sops.yaml"
