#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

talosctl config context ${CLUSTER_NAME}

talosctl apply-config \
  --insecure \
  -e ${C1_IP} \
  -n ${C3_IP} \
  --file clusterconfig/${CLUSTER_NAME}-${C3_HOST}.yaml

echo "⏳ Giving node time to fully start up before approving certs..."
read -rp "Press any key to approve certs: " continuecertc2sanswer

kubectl get \
  csr \
  -o name | xargs kubectl certificate approve
