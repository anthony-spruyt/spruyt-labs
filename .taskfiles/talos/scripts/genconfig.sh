#!/bin/bash
set -euo pipefail

TALOS_DIR="/workspaces/spruyt-labs/talos"
CLUSTERCONFIG_DIR="${TALOS_DIR}/clusterconfig"

# The install disk is declared twice: talhelper rejects a node without
# installDiskSelector, and the patch file is what topf will use. The patch is applied
# last, so it wins - editing only talconfig.yaml would silently install to the old disk.
# Removed with talhelper in issue #2637 phase 2.
while read -r host; do
  patch="${TALOS_DIR}/patches/node/${host}/configure-install-disk.yaml"
  [[ -f "${patch}" ]] || continue
  declared=$(yq eval ".nodes[] | select(.hostname == \"${host}\") | .installDiskSelector.serial" "${TALOS_DIR}/talconfig.yaml")
  patched=$(yq eval '.machine.install.diskSelector.serial' "${patch}")
  if [[ "${declared}" != "${patched}" ]]; then
    echo "install disk serial mismatch for ${host}: talconfig.yaml has ${declared}, ${patch} has ${patched}" >&2
    exit 1
  fi
done < <(yq eval '.nodes[].hostname' "${TALOS_DIR}/talconfig.yaml")

talhelper validate talconfig "${TALOS_DIR}/talconfig.yaml" \
  -e "${TALOS_DIR}/talenv.sops.yaml"

talhelper genconfig \
  -c "${TALOS_DIR}/talconfig.yaml" \
  -e "${TALOS_DIR}/talenv.sops.yaml" \
  -s "${TALOS_DIR}/talsecret.sops.yaml" \
  -o "${CLUSTERCONFIG_DIR}" \
  -m metal

# Workaround: talhelper puts VIP on parent interface (enp1s0) instead of
# VLAN sub-interface (enp1s0.20). Upstream: budimanjojo/talhelper#1390
for cfg in "${CLUSTERCONFIG_DIR}"/spruyt-labs-e2-*.yaml; do
  if yq eval-all 'select(.kind == "Layer2VIPConfig") | .link' "$cfg" 2>/dev/null | grep -q "^enp1s0$"; then
    yq eval-all '(select(.kind == "Layer2VIPConfig") | .link) = "enp1s0.20"' -i "$cfg"
    echo "Patched Layer2VIPConfig link to enp1s0.20 in $(basename "$cfg")"
  fi
done

TALOSCONFIG="${CLUSTERCONFIG_DIR}/talosconfig"
if [[ -f "${TALOSCONFIG}" ]]; then
  if talosctl config merge "${TALOSCONFIG}" 2>/dev/null; then
    echo "Merged talosconfig into local talosctl config"
  else
    echo "Skipped talosctl config merge (config may be read-only)"
  fi
fi

talosctl config info
