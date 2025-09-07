#!/bin/bash
set -euo pipefail

find /workspaces/spruyt-labs -type f -name '*.sops.yaml' \
  ! -name '.sops.yaml' \
  ! -name 'talsecret.sops.yaml' \
  -exec sops --config "/workspaces/spruyt-labs/.sops.yaml" --decrypt --in-place {} \;
