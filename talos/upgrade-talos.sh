#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# TODO: need to update script to show rook-ceph status as healthy before upgrading and needs to be waited for between each node upgrade
# https://www.talos.dev/v1.10/kubernetes-guides/configuration/ceph-with-rook/#talos-linux-considerations

$ talosctl upgrade \
  --nodes ${C1_IP} \
  --image factory.talos.dev/metal-installer-secureboot/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774:v1.10.5 \
  --preserve

echo "⏳ Giving control plane time to upgrade before upgrading the next node..."
read -rp "Press any key to continue: " continueupgrade1answer

$ talosctl upgrade \
  --nodes ${C2_IP} \
  --image factory.talos.dev/metal-installer-secureboot/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774:v1.10.5 \
  --preserve

echo "⏳ Giving control plane time to upgrade before upgrading the next node..."
read -rp "Press any key to continue: " continueupgrade2answer

$ talosctl upgrade \
  --nodes ${C3_IP} \
  --image factory.talos.dev/metal-installer-secureboot/777390ee380b57c5589bda8c3c3673d6b1e3252add27737701d216fbd50a3774:v1.10.5 \
  --preserve
