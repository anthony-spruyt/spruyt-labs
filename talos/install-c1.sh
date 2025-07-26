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

# Uncomment below if did not run generate yet in new dev container
# talosctl config remove dummy -y || true
# talosctl config add dummy
# talosctl config context dummy
# talosctl config remove ${CLUSTER_NAME} -y || true
# talosctl config merge clusterconfig/talosconfig
# talosctl config context ${CLUSTER_NAME}
#
# talosctl config endpoint ${C1_IP}
# talosctl config node ${C1_IP}
#
# talosctl config remove dummy -y
#
# talosctl config info

talosctl config context ${CLUSTER_NAME}

talosctl apply-config \
  --insecure \
  -e ${C1_IP} \
  -n ${C1_IP} \
  --file clusterconfig/${CLUSTER_NAME}-${C1_HOST}.yaml

wait_for_talos "${C1_IP}" 300

echo "⏳ Giving control plane components time to fully start up before bootstrapping..."
read -rp "Press any key to continue: " continuebootstrapanswer

talosctl bootstrap \
  -e ${C1_IP} \
  -n ${C1_IP}

wait_for_bootstrap "${C1_IP}" 300

talosctl kubeconfig \
  -e ${C1_IP} \
  -n ${C1_IP} \
  -f \
  -m

echo "⏳ Giving control plane components time to fully bootstrap before installing cilium..."
read -rp "Press any key to continue: " continueciliumanswer

helmfile apply \
  --suppress-diff \
  -f helmfile/cilium.yaml

echo "⏳ Giving cilium time to fully start up before approving certs..."
read -rp "Press any key to approve certs: " continuecertc1sanswer

kubectl get \
  csr \
  -o name | xargs kubectl certificate approve

kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

#kubectl delete secret sops-age --namespace=flux-system
cat /workspaces/spruyt-labs/secrets/age.key | kubectl create secret generic sops-age --namespace=flux-system --from-file=age.agekey=/dev/stdin

#read -rp "Press any key to gh auth login: " continueghanswer

#gh auth login

#read -rp "Press any key to gh auth: " continueghanswer

gh auth token | helm registry login ghcr.io -u anthony-spruyt --password-stdin

#read -rp "Press any key to add flux-gitops-key secret to cluster: " continuegitopsanswer

ssh-keyscan github.com > /workspaces/spruyt-labs/secrets/known_hosts

kubectl create secret generic flux-gitops-key \
  --namespace=flux-system \
  --from-file=identity=/workspaces/spruyt-labs/secrets/flux-gitops-key \
  --from-file=known_hosts=/workspaces/spruyt-labs/secrets/known_hosts

# https://github.com/kubernetes-csi/external-snapshotter?tab=readme-ov-file#usage
echo "⏳ Installing external-snapshotter CRDs..."
kubectl kustomize https://github.com/kubernetes-csi/external-snapshotter/client/config/crd | kubectl create -f -
echo "⏳ Installing cert-manager CRDs..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.2/cert-manager.crds.yaml

read -rp "Press any key to install flux: " continuefluxanswer

helmfile apply \
  --suppress-diff \
  -f helmfile/flux.yaml
