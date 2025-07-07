#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

echo "Generating Talos configuration for cluster ${CLUSTER_NAME}..."

talosctl gen config ${CLUSTER_NAME} https://${CONTROL_PLANE_1_NODE_IP}:6443 \
  --with-secrets ${TALOS_SECRETS_PATH} \
  --output-types talosconfig \
  --output ${TALOS_OUTPUT_PATH}/talosconfig \
  --force

talosctl gen config ${CLUSTER_NAME} https://${CONTROL_PLANE_1_NODE_IP}:6443 \
  --config-patch-control-plane @${TALOS_PATCHES_PATH}/allow-scheduling-on-control-planes.yaml \
  --config-patch-control-plane @${TALOS_PATCHES_PATH}/disable-flannel.yaml \
  --config-patch-control-plane @${TALOS_PATCHES_PATH}/disable-kubeproxy.yaml \
  --install-disk ${CONTROL_PLANE_1_DISK} \
  --with-secrets ${TALOS_SECRETS_PATH} \
  --output-types controlplane \
  --output ${TALOS_OUTPUT_PATH}/controlplane.yaml \
  --force

talosctl machineconfig patch ${TALOS_OUTPUT_PATH}/controlplane.yaml \
  --patch "[ \
    {\"op\":\"add\",\"path\":\"/machine/network/hostname\",\"value\":\"${CONTROL_PLANE_1_HOSTNAME}\"} \
  ]" \
  --patch @${TALOS_PATCHES_PATH}/wipe-disk.yaml \
  > ${TALOS_OUTPUT_PATH}/controlplane.${CONTROL_PLANE_1_HOSTNAME}.yaml

talosctl gen config ${CLUSTER_NAME} https://${CONTROL_PLANE_1_NODE_IP}:6443 \
  --install-disk ${WORKER_1_DISK} \
  --with-secrets ${TALOS_SECRETS_PATH} \
  --output-types worker \
  --output ${TALOS_OUTPUT_PATH}/worker.yaml \
  --force

talosctl machineconfig patch ${TALOS_OUTPUT_PATH}/worker.yaml \
  --patch "[ \
    {\"op\":\"add\",\"path\":\"/machine/network/hostname\",\"value\":\"${WORKER_1_NODE_IP}\"} \
  ]" \
  --patch @${TALOS_PATCHES_PATH}/wipe-disk.yaml \
  > ${TALOS_OUTPUT_PATH}/worker.${WORKER_1_HOSTNAME}.yaml

talosctl config remove dummy -y || true
talosctl config add dummy
talosctl config context dummy
talosctl config remove ${CLUSTER_NAME} -y || true
talosctl config merge ${TALOS_OUTPUT_PATH}/talosconfig
talosctl config context ${CLUSTER_NAME}

talosctl config endpoint ${CONTROL_PLANE_1_NODE_IP}
talosctl config node ${CONTROL_PLANE_1_NODE_IP}

talosctl config remove dummy -y

talosctl config info

rm -f ${TALOS_OUTPUT_PATH}/talosconfig
rm -f ${TALOS_OUTPUT_PATH}/controlplane.yaml
rm -f ${TALOS_OUTPUT_PATH}/worker.yaml

echo "Control Plane 1 Configuration: ${TALOS_OUTPUT_PATH}/controlplane.${CONTROL_PLANE_1_HOSTNAME}.yaml"
echo "Worker 1 Configuration: ${TALOS_OUTPUT_PATH}/worker.${WORKER_1_HOSTNAME}.yaml"
echo "Talos Config: ${TALOS_OUTPUT_PATH}/talosconfig"
