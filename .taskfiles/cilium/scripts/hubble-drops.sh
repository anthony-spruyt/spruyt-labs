#!/bin/bash
set -euo pipefail

# Show recent dropped flows (last 100)
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED --last 100
