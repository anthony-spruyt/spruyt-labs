#!/bin/bash
set -euo pipefail

# Kill any existing port-forward to hubble-relay
pkill -f "port-forward.*hubble-relay" 2>/dev/null || true

# Start port-forward in background
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &
PF_PID=$!

# Wait for port-forward to be ready
sleep 2

# Show dropped traffic
hubble observe --verdict DROPPED --last 100 -o compact || true

# Cleanup
kill $PF_PID 2>/dev/null || true
