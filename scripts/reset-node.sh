#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

read -rp "Reset control plane 1? (y/n): " resetc1answer
if [[ "$resetc1answer" =~ ^[Yy]$ ]]; then
  echo "Resetting node ${CONTROL_PLANE_1_NODE_IP}..."
  talosctl reset -n ${CONTROL_PLANE_1_NODE_IP} --reboot --graceful=false
elif [[ "$resetc1answer" =~ ^[Nn]$ ]]; then
  echo "Skipping reset for control plane 1."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi

read -rp "Reset worker 1? (y/n): " resetw1answer
if [[ "$resetw1answer" =~ ^[Yy]$ ]]; then
  echo "Resetting node ${WORKER_1_NODE_IP}..."
  talosctl reset -n ${WORKER_1_NODE_IP} --reboot --graceful=false
elif [[ "$resetw1answer" =~ ^[Nn]$ ]]; then
  echo "Skipping reset for worker 1."
else
  echo "Invalid input. Exiting by default."
  exit 1
fi
