#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/resolve.sh"

CLUSTER_NAME=$(resolve_cluster_name)
CONFIGDIR="/workspaces/spruyt-labs/talos/clusterconfig"

for hostname in $(yq '.nodes[].hostname' /workspaces/spruyt-labs/talos/talconfig.yaml); do
  ip=$(resolve_node_ip "${hostname}")
  echo "Applying config to ${hostname} (${ip})..."
  talosctl apply-config -n "${ip}" -f "${CONFIGDIR}/${CLUSTER_NAME}-${hostname}.yaml" -m=auto
done
