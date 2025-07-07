#!/bin/bash
set -euo pipefail

kubectl get kustomization -A
flux reconcile kustomization flux-system --with-source
#flux reconcile helmrelease cilium -n kube-system --with-source
