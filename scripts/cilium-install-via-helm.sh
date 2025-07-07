#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

./helm-install.sh

helm template \
    cilium \
    cilium/cilium \
    --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    -f "${CILIUM_VALUES_PATH}" \
    > "${TALOS_OUTPUT_PATH}/cilium.yaml"

while true; do
  if kubectl apply -f "${TALOS_OUTPUT_PATH}/cilium.yaml"; then
    break
  fi
  echo "❌ Cilium install failed. Press Enter to retry, or type 'q' then Enter to quit."
  read -r ans
  if [[ "$ans" == "q" ]]; then
    exit 1
  fi
done

start_time=$SECONDS
while true; do
  if kubectl -n kube-system get pods -l k8s-app=cilium 2>/dev/null | grep -v NAME | grep -qv 'Pending\|ContainerCreating\|CrashLoopBackOff\|Error'; then
    echo "✅ Cilium pods are ready."
    break
  fi

  if (( SECONDS - start_time > TIMEOUT )); then
    echo "❌ Timeout reached after $TIMEOUT seconds. Cilium pods did not become ready."
    exit 1
  fi

  echo "🔄 Still waiting for Cilium pods..."
  sleep 5
done
