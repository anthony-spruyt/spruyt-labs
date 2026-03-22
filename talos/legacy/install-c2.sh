#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/talos/config.sh"

wait_for_talos() {
  local node_ip="$1"
  local timeout="${2:-300}" # default: 5 minutes
  local interval=5
  local elapsed=0

  echo "⏳ Waiting for Talos node at ${node_ip} to respond..."

  while ! talosctl version -n "${node_ip}" &>/dev/null; do
    sleep "${interval}"
    elapsed=$((elapsed + interval))

    if ((elapsed >= timeout)); then
      echo "❌ Timeout waiting for Talos node at ${node_ip} to respond."
      return 1
    fi
  done

  echo "✅ Talos node at ${node_ip} is responsive."
  return 0
}

talosctl config context "${CLUSTER_NAME}"

talosctl apply-config \
  --insecure \
  -e "${C1_IP4}" \
  -n "${C2_IP4}" \
  --file "clusterconfig/${CLUSTER_NAME}-${C2_HOST}.yaml"

wait_for_talos "${C2_IP4}" 300

echo "⏳ Giving node time to fully start up before wiping secondary disks..."
read -rp "Press any key to wipe secondary disks: "

talosctl wipe disk nvme0n1 -n "${C2_IP4}" --drop-partition

echo "⏳ Giving node time to fully start up before approving certs..."
read -rp "Press any key to approve certs: "

kubectl get \
  csr \
  -o name | xargs kubectl certificate approve

#read -rp "Press any key to install flux: "
#
#helmfile apply \
#  --suppress-diff \
#  -f helmfile/flux.yaml
