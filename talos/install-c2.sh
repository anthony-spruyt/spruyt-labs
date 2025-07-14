#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Uncomment below if did not run generate yet in new dev container
# talosctl config remove dummy -y || true
# talosctl config add dummy
# talosctl config context dummy
# talosctl config remove ${CLUSTER_NAME} -y || true
# talosctl config merge clusterconfig/talosconfig
# talosctl config context ${CLUSTER_NAME}
#
# talosctl config endpoint ${C1_IP}
# talosctl config node ${C1_IP}
#
# talosctl config remove dummy -y
#
# talosctl config info

talosctl config context ${CLUSTER_NAME}

talosctl apply-config \
  --insecure \
  -e ${C1_IP} \
  -n ${C2_IP} \
  --file clusterconfig/${CLUSTER_NAME}-ctrl-e2-2.yaml

echo "⏳ Giving node time to fully start up before approving certs..."
read -rp "Press any key to approve certs: " continuecertc2sanswer

kubectl get \
  csr \
  -o name | xargs kubectl certificate approve
