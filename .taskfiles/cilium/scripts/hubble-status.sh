#!/bin/bash
set -euo pipefail

# Show Hubble status and flow buffer capacity
kubectl exec -n kube-system ds/cilium -- cilium-dbg status --verbose | grep -A2 "Hubble"
