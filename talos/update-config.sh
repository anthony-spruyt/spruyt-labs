#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

talosctl apply-config -n ${C1_IP} -f /workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C1_HOST}.yaml -m=auto
talosctl apply-config -n ${C2_IP} -f /workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C2_HOST}.yaml -m=auto
