#!/bin/bash
set -euo pipefail

source "/workspaces/spruyt-labs/talos/config.sh"

export SOPS_AGE_KEY_FILE="/workspaces/spruyt-labs/secrets/age.key"

#read -rp "Generate secrets? (y/n): " gensecretsanswer
#if [[ "$gensecretsanswer" =~ ^[Yy]$ ]]; then
#  talhelper gensecret > /workspaces/spruyt-labs/talos/talsecret.sops.yaml
#  sops --config "/workspaces/spruyt-labs/.sops.yaml" -e --in-place "/workspaces/spruyt-labs/talos/talsecret.sops.yaml"
#fi

talhelper validate talconfig \
  -e talenv.sops.yaml
talhelper genconfig \
  -c talconfig.yaml \
  -e talenv.sops.yaml \
  -s talsecret.sops.yaml \
  -m metal #--debug

#talosctl config remove dummy -y || true
#talosctl config add dummy
#talosctl config context dummy
#talosctl config remove ${CLUSTER_NAME} -y || true
#talosctl config merge clusterconfig/talosconfig
#talosctl config context ${CLUSTER_NAME}
#
#talosctl config endpoint ${C1_IP4}
#talosctl config node ${C1_IP4}
#
#talosctl config remove dummy -y
#
#talosctl config info
