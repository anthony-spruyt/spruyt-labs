#!/bin/bash
set -euo pipefail

TALOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/talos"

# topf falls back to writing plaintext when sops is missing, and the bundle it
# writes is the cluster PKI. Inside the devcontainer sops is a pinned feature, but
# these tasks also run from Coder workspaces and bare clones - fail closed there.
for bin in topf sops vals; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "required binary not found on PATH: ${bin}" >&2
    exit 1
  fi
done

# vals resolves the ref+sops:// paths in topf.yaml against the working directory
cd "${TALOS_DIR}"

exec topf "$@"
