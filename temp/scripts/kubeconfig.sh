#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

talosctl config context ${CLUSTER_NAME}

talosctl kubeconfig . \
  --nodes ${CONTROL_PLANE_1_NODE_IP} \
  --endpoints ${CONTROL_PLANE_1_NODE_IP}
  