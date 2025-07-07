#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

echo "Bootstrapping cluster ${CLUSTER_NAME}..."

talosctl config context ${CLUSTER_NAME}

talosctl bootstrap \
    --nodes ${CONTROL_PLANE_1_NODE_IP} \
    --endpoints ${CONTROL_PLANE_1_NODE_IP}