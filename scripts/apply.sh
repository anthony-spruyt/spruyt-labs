#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

wait_for_talos() {
  local node_ip="$1"
  local timeout="${2:-300}"  # default: 5 minutes
  local interval=5
  local elapsed=0

  echo "⏳ Waiting for Talos node at ${node_ip} to respond..."

  while ! talosctl version -n "${node_ip}" &>/dev/null; do
    sleep "${interval}"
    elapsed=$((elapsed + interval))

    if (( elapsed >= timeout )); then
      echo "❌ Timeout waiting for Talos node at ${node_ip} to respond."
      return 1
    fi
  done

  echo "✅ Talos node at ${node_ip} is responsive."
  return 0
}

wait_for_bootstrap() {
  local endpoint_ip="$1"
  local timeout="${2:-300}"  # default: 5 minutes
  local interval=5
  local elapsed=0

  echo "⏳ Waiting for Kubernetes API to become available at ${endpoint_ip}..."

  while ! talosctl -n "${endpoint_ip}" --endpoints "${endpoint_ip}" kubeconfig &>/dev/null; do
    sleep "${interval}"
    elapsed=$((elapsed + interval))

    if (( elapsed >= timeout )); then
      echo "❌ Timeout waiting for Kubernetes API to become available."
      return 1
    fi
  done

  echo "✅ Kubernetes API is up and bootstrap is complete."
  return 0
}

wait_for_node_ready() {
  local node_name="$1"
  local timeout="${2:-300}"
  local interval=5
  local elapsed=0

  echo "⏳ Waiting for node '${node_name}' to be Ready..."

  while true; do
    status=$(kubectl get node "${node_name}" --no-headers 2>/dev/null | awk '{print $2}')
    if [[ "$status" == "Ready" ]]; then
      echo "✅ Node '${node_name}' is Ready."
      return 0
    fi

    sleep "${interval}"
    elapsed=$((elapsed + interval))
    if (( elapsed >= timeout )); then
      echo "❌ Timeout waiting for node '${node_name}' to be Ready."
      return 1
    fi
  done
}

echo "Applying configuration for cluster ${CLUSTER_NAME}..."

talosctl config context ${CLUSTER_NAME}

read -rp "Apply configuration to control plane 1? (y/n): " applyc1answer
if [[ "$applyc1answer" =~ ^[Yy]$ ]]; then
  echo "Applying control plane 1 configuration to node ${CONTROL_PLANE_1_NODE_IP}..."
  talosctl apply-config --insecure \
    -n ${CONTROL_PLANE_1_NODE_IP} \
    --file ${TALOS_OUTPUT_PATH}/controlplane.${CONTROL_PLANE_1_HOSTNAME}.yaml
    wait_for_talos "${CONTROL_PLANE_1_NODE_IP}" 300
    read -rp "Bootstrap cluster? (y/n): " bootstrapanswer
    if [[ "$bootstrapanswer" =~ ^[Yy]$ ]]; then
      ./bootstrap.sh
      wait_for_bootstrap "${CONTROL_PLANE_1_NODE_IP}" 300
      echo "⏳ Giving control plane components time to fully start up before installing cilium..."
      read -rp "Press any key to continue: " continue1answer
      ./cilium-install-via-helm.sh
    elif [[ "$bootstrapanswer" =~ ^[Nn]$ ]]; then
      echo "Skipping bootstrap."
    else
      echo "Invalid input. Exiting by default."
      exit 1
    fi
elif [[ "$applyc1answer" =~ ^[Nn]$ ]]; then
  echo "Skipping control plane 1 configuration application and bootstrapping."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi

read -rp "Apply configuration to worker 1? (y/n): " applyw1answer
if [[ "$applyw1answer" =~ ^[Yy]$ ]]; then
  echo "Applying worker 1 configuration to node ${WORKER_1_NODE_IP}..."
  talosctl apply-config --insecure \
    -n ${WORKER_1_NODE_IP} \
    --file ${TALOS_OUTPUT_PATH}/worker.${WORKER_1_HOSTNAME}.yaml
  wait_for_talos "${WORKER_1_NODE_IP}" 300
elif [[ "$applyw1answer" =~ ^[Nn]$ ]]; then
  echo "Skipping worker 1 configuration application."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi
