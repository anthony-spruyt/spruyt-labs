#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/talos/config.sh"

talosctl apply-config -n "${C1_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C1_HOST}.yaml" -m=auto  # reboot | auto
talosctl apply-config -n "${C2_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C2_HOST}.yaml" -m=auto  # reboot | auto
talosctl apply-config -n "${C3_IP4}" -f "/workspaces/spruyt-labs/talos/clusterconfig/${CLUSTER_NAME}-${C3_HOST}.yaml" -m=auto  # reboot | auto
