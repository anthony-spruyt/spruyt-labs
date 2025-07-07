#!/bin/bash
set -euo pipefail

# resolve this script’s directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# 1) Ensure yq is present
if ! command -v yq &> /dev/null; then
  echo "🔧 yq not found. Trying Snap install…"
  if command -v snap &> /dev/null; then
    sudo snap install yq
  else
    echo "⚠️ Snap unavailable. Downloading yq binary…"
    sudo wget -qO /usr/local/bin/yq \
      https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod +x /usr/local/bin/yq
  fi
fi

# 2) Ensure kubeconform is present
if ! command -v kubeconform &> /dev/null; then
  echo "🔧 kubeconform not found. Downloading…"
  curl -sL \
    https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz \
    | tar xzvf - kubeconform
  sudo mv kubeconform /usr/local/bin/
fi

# 3) Install Flux components
echo "🔨 Installing Flux components…"
"${SCRIPT_DIR}/flux-install.sh"
read -p "✅ Flux installed. Press Enter to build kustomization…"

# 4) Build manifests via Flux
echo "🧱 Building Flux kustomization…"
flux build kustomization flux-system \
  --path "${FLUX_PATH}" \
  > "${FLUX_TEST_PATH}/rendered.yaml"
read -p "✅ Kustomization built. Press Enter to run kubeconform…"

# 5) Validate schemas
echo "🔍 Validating with kubeconform…"
kubeconform -summary -strict -ignore-missing-schemas \
  "${FLUX_TEST_PATH}/rendered.yaml"
read -p "✅ Schema validated. Press Enter to run kubectl diff…"

# 6) Diff check
echo "🧪 Running kubectl diff…"
kubectl diff -f "${FLUX_TEST_PATH}/rendered.yaml" || true
read -p "✅ Diff completed. Press Enter to run guardrail checks…"

# 7) Guardrail validation
echo "🛡️ Running guardrail checks…"
"${SCRIPT_DIR}/check-guardrails.sh" || {
  echo "🚫 Guardrail block triggered. Halting sync."
  exit 1
}
read -p "✅ Guardrails passed. Press Enter to preview critical resources…"

# 8) Preview high-impact resources
echo "🧹 Filtering critical resources…"
kubectl apply \
  -f "${FLUX_TEST_PATH}/rendered.yaml" \
  --dry-run=client \
  -o yaml | yq e '
    select(
      .kind == "Ingress" or
      .kind == "Certificate" or
      .kind == "ClusterIssuer" or
      .kind == "HelmRelease" or
      .kind == "Kustomization" or
      .kind == "GitRepository" or
      .kind == "Namespace" or
      .kind == "NetworkPolicy" or
      .kind == "Service" or
      .kind == "Deployment" or
      .kind == "CiliumClusterwideNetworkPolicy"
    )
  ' -
echo "✅ All pre-sync tests complete. Ready for liftoff."