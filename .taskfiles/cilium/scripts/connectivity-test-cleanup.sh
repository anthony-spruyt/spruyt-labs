#!/bin/bash
set -euo pipefail

# Clean up leftover namespaces from failed connectivity tests
echo "Deleting namespaces with label cilium.io/connectivity-test=true..."
kubectl delete ns -l cilium.io/connectivity-test=true --ignore-not-found
echo "Cleanup complete."
