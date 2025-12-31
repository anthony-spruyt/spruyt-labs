#!/bin/bash
set -euo pipefail

# Show drops for a specific namespace
# Usage: ./hubble-drops-ns.sh <namespace>

NAMESPACE="${1:?Usage: $0 <namespace>}"
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED \
  --from-namespace "$NAMESPACE" --to-namespace "$NAMESPACE" --last 100
