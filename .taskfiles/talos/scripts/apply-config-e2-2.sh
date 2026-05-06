#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/resolve.sh"

HOSTNAME="e2-2"
CLUSTER_NAME=$(resolve_cluster_name)
IP=$(resolve_node_ip "${HOSTNAME}")
talosctl apply-config -n "${IP}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${HOSTNAME}.yaml" -m=auto
