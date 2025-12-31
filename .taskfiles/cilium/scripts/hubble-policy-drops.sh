#!/bin/bash
set -euo pipefail

# Show only policy-related drops
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED --type policy-verdict --last 100
