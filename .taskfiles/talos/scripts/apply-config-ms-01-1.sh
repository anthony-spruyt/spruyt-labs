#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/.taskfiles/talos/scripts/config.sh"

talosctl apply-config -n "${W1_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${W1_HOST}.yaml" -m=auto # reboot | auto
