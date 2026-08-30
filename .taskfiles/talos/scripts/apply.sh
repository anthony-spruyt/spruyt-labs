#!/bin/bash
set -euo pipefail

# NODE is a Go regex matched against topf.yaml hosts; empty means every node.
# topf applies control-plane nodes one at a time regardless.
#
# With --dry-run topf exits 2 when it finds drift, and that propagates. Treat a non-zero
# exit from `task talos:diff` as "there is drift", not as a broken command.
NODE="${NODE:-}"

args=()
if [[ -n "${NODE}" ]]; then
  args+=(--nodes-filter "${NODE}")
fi

bash "$(dirname "$0")/topf.sh" "${args[@]}" apply "$@"
