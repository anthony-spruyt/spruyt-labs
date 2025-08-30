#!/bin/bash
set -euo pipefail

export SOPS_AGE_KEY_FILE="/workspaces/spruyt-labs/secrets/age.key"

find /workspaces/spruyt-labs -type f -name '*.sops.yaml' \
  ! -name '.sops.yaml' \
  ! -name 'talsecret.sops.yaml' \
  -exec sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place {} \;
