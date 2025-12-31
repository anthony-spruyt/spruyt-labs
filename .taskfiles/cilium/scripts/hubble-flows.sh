#!/bin/bash
set -euo pipefail

# Show recent flows (last 100)
kubectl exec -n kube-system ds/cilium -- hubble observe --last 100
