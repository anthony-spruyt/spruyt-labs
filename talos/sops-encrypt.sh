#!/bin/bash
set -euo pipefail

export SOPS_AGE_KEY_FILE="/workspaces/spruyt-labs/secrets/age.key"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/talos/talenv.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/flux/meta/cluster-secrets.sops.yaml"
