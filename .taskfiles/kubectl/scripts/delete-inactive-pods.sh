#!/bin/bash
set -euo pipefail

kubectl get pods --all-namespaces --field-selector=status.phase=Failed \
  -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name] | @tsv' \
  | xargs -r -n2 sh -c 'kubectl delete pod "$1" -n "$0"'

kubectl get pods --all-namespaces --field-selector=status.phase=Succeeded \
  -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name] | @tsv' \
  | xargs -r -n2 sh -c 'kubectl delete pod "$1" -n "$0"'
