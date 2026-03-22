#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/.taskfiles/talos/scripts/config.sh"

talosctl apply-config -n "${C1_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C1_HOST}.yaml" -m=auto # reboot | auto
talosctl apply-config -n "${C2_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C2_HOST}.yaml" -m=auto # reboot | auto
talosctl apply-config -n "${C3_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C3_HOST}.yaml" -m=auto # reboot | auto
talosctl apply-config -n "${W1_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${W1_HOST}.yaml" -m=auto # reboot | auto
talosctl apply-config -n "${W2_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${W2_HOST}.yaml" -m=auto # reboot | auto
talosctl apply-config -n "${W3_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${W3_HOST}.yaml" -m=auto # reboot | auto
