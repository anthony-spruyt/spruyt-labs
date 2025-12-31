#!/bin/bash
set -euo pipefail

# Port-forward Hubble Relay for local CLI access
echo "Starting port-forward to Hubble Relay..."
echo "Use 'hubble observe --server localhost:4245' to connect"
kubectl -n kube-system port-forward svc/hubble-relay 4245:80
