#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/.taskfiles/talos/scripts/config.sh"

talosctl apply-config -n "${W2_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${W2_HOST}.yaml" -m=auto  # reboot | auto
