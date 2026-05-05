#!/bin/bash
set -euo pipefail

TALOS_DIR="/workspaces/spruyt-labs/talos"
CLUSTERCONFIG_DIR="${TALOS_DIR}/clusterconfig"

talhelper validate talconfig "${TALOS_DIR}/talconfig.yaml" \
  -e "${TALOS_DIR}/talenv.sops.yaml"

talhelper genconfig \
  -c "${TALOS_DIR}/talconfig.yaml" \
  -e "${TALOS_DIR}/talenv.sops.yaml" \
  -s "${TALOS_DIR}/talsecret.sops.yaml" \
  -o "${CLUSTERCONFIG_DIR}" \
  -m metal

TALOSCONFIG="${CLUSTERCONFIG_DIR}/talosconfig"
if [[ -f "${TALOSCONFIG}" ]]; then
  if talosctl config merge "${TALOSCONFIG}" 2>/dev/null; then
    echo "Merged talosconfig into local talosctl config"
  else
    echo "Skipped talosctl config merge (config may be read-only)"
  fi
fi

talosctl config info
