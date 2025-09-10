#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/talos/config.sh"

# TODO: need to update script to show rook-ceph status as healthy before upgrading and needs to be waited for between each node upgrade
# https://www.talos.dev/v1.10/kubernetes-guides/configuration/ceph-with-rook/#talos-linux-considerations

talosctl upgrade \
  --nodes "${C1_IP4}" \
  --image factory.talos.dev/metal-installer-secureboot/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61:v1.10.7 \
  --preserve \
  --force

echo "⏳ Giving control plane time to upgrade before upgrading the next node..."
read -rp "Press any key to continue: "
talosctl upgrade \
  --nodes "${C2_IP4}" \
  --image factory.talos.dev/metal-installer-secureboot/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61:v1.10.7 \
  --preserve \
  --force

echo "⏳ Giving control plane time to upgrade before upgrading the next node..."
read -rp "Press any key to continue: "
talosctl upgrade \
  --nodes "${C3_IP4}" \
  --image factory.talos.dev/metal-installer-secureboot/9aa2ecda3ee602d57be72bb3c9b43fc6bc37c7279ea5b36c4e84d91d55853d61:v1.10.7 \
  --preserve \
  --force
