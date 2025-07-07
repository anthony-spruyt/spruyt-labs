#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

echo "Generating secrets for cluster ${CLUSTER_NAME}..."

talosctl gen secrets -o ../secrets/talos.yaml --force
