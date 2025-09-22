#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/talos/config.sh"

# TODO: need to update script to show rook-ceph status as healthy before upgrading and needs to be waited for between each node upgrade
# https://www.talos.dev/v1.10/kubernetes-guides/configuration/ceph-with-rook/#talos-linux-considerations

talosctl upgrade \
  --nodes "${C1_IP4}" \
  --image factory.talos.dev/metal-installer-secureboot/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb:v1.10.7 \
  --preserve \
  --force

echo "⏳ Giving control plane time to upgrade before upgrading the next node..."
read -rp "Press any key to continue: "
talosctl upgrade \
  --nodes "${C2_IP4}" \
  --image factory.talos.dev/metal-installer-secureboot/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb:v1.10.7 \
  --preserve \
  --force

echo "⏳ Giving control plane time to upgrade before upgrading the next node..."
read -rp "Press any key to continue: "
talosctl upgrade \
  --nodes "${C3_IP4}" \
  --image factory.talos.dev/metal-installer-secureboot/1d6296ab0966f9bd87ec25c8fc39f15b15768c33fc1cccd52a8c098a930fbafb:v1.10.7 \
  --preserve \
  --force
