#!/bin/bash
set -euo pipefail

export SOPS_AGE_KEY_FILE="/workspaces/spruyt-labs/secrets/age.key"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --decrypt --in-place "/workspaces/spruyt-labs/talos/talenv.sops.yaml"
#sops --config "/workspaces/spruyt-labs/.sops.yaml" --decrypt --in-place "/workspaces/spruyt-labs/talos/talsecret.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --decrypt --in-place "/workspaces/spruyt-labs/cluster/flux/meta/cluster-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --decrypt --in-place "/workspaces/spruyt-labs/cluster/apps/rook-ceph/rook-ceph-cluster/storage-encryption-secret.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --decrypt --in-place "/workspaces/spruyt-labs/cluster/apps/cert-manager/cert-manager/solver-secrets.sops.yaml"
