#!/bin/bash
set -euo pipefail

# Show flows for a specific namespace
# Usage: ./hubble-flows-ns.sh <namespace>

NAMESPACE="${1:?Usage: $0 <namespace>}"
kubectl exec -n kube-system ds/cilium -- hubble observe \
  --from-namespace "$NAMESPACE" --to-namespace "$NAMESPACE" --last 100
