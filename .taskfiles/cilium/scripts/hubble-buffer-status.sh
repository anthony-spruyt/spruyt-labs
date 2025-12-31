#!/bin/bash
set -euo pipefail

# Check Hubble ring buffer utilization across all nodes
for pod in $(kubectl get pods -n kube-system -l k8s-app=cilium -o name); do
  echo "=== $pod ==="
  kubectl exec -n kube-system "$pod" -- cilium-dbg status 2>/dev/null | grep -E "Hubble|Flows"
done
