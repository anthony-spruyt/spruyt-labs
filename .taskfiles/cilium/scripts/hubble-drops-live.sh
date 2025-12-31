#!/bin/bash
set -euo pipefail

# Stream dropped flows in real-time
kubectl exec -n kube-system ds/cilium -- hubble observe --verdict DROPPED -f
