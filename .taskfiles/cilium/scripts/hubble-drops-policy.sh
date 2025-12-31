#!/bin/bash
set -euo pipefail

# Show drops with policy match info
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED --last 100 -o compact
