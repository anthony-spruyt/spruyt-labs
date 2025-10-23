#!/bin/bash
set -euo pipefail

kubectl patch pv "$1" --type=json \
  -p='[{"op": "remove", "path": "/spec/claimRef"}]'
kubectl patch pv "$1" --type=json \
  -p='[{"op": "replace", "path": "/spec/accessModes", "value": ["ReadWriteOnce"]}]'
