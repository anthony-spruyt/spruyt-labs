#!/bin/bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# This installs Cilium manually to ensure cluster networking before Flux/Helm Release can manage it.
# Flux/Helm will reconcile Cilium in GitOps style once the cluster is online.

# --- Ensure cilium is installed ---
if ! command -v cilium &> /dev/null; then
  echo "🔧 Cilium CLI not found. Installing latest Cilium CLI..."
  CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  OS=$(uname | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH=amd64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  TMP_DIR=$(mktemp -d)
  curl -Lo "${TMP_DIR}/cilium.tar.gz" \
    "https://github.com/cilium/cilium-cli/releases/download/v${CLI_VERSION}/cilium-${OS}-${ARCH}.tar.gz"
  tar -xzf "${TMP_DIR}/cilium.tar.gz" -C "${TMP_DIR}"
  sudo mv "${TMP_DIR}/cilium" /usr/local/bin/cilium
  rm -rf "${TMP_DIR}"

  echo "✅ Cilium CLI installed. Version: $(cilium version --client)"
else
  echo "✅ Cilium CLI is already installed. Version: $(cilium version --client)"
fi

while true; do
  cilium install \
    --set ipam.mode=kubernetes \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=localhost \
    --set k8sServicePort=7445 \
    --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set cgroup.autoMount.enabled=false \
    --set cgroup.hostRoot=/sys/fs/cgroup
  status=$?
  if [ $status -eq 0 ]; then
    break
  fi
  echo "❌ Cilium install failed. Press Enter to retry, or type 'q' then Enter to quit."
  read -r ans
  [ "$ans" = "q" ] && exit 1
done

echo "⏳ Waiting for Cilium pods to be ready (timeout: 5 minutes)..."
SECONDS=0
TIMEOUT=300

while true; do
  if kubectl -n kube-system get pods -l k8s-app=cilium 2>/dev/null | grep -v NAME | grep -qv 'Pending\|ContainerCreating\|CrashLoopBackOff\|Error'; then
    echo "✅ Cilium pods are ready."
    break
  fi

  if [ $SECONDS -gt $TIMEOUT ]; then
    echo "❌ Timeout reached after 5 minutes. Cilium pods did not become ready."
    exit 1
  fi

  echo "🔄 Still waiting for Cilium pods..."
  sleep 5
done