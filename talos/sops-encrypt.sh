#!/bin/bash
set -euo pipefail

export SOPS_AGE_KEY_FILE="/workspaces/spruyt-labs/secrets/age.key"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/talos/talenv.sops.yaml"
#sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/talos/talsecret.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/flux/meta/cluster-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/rook-ceph/rook-ceph-cluster/app/storage-encryption-secret.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/cert-manager/cert-manager/app/solver-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/cert-manager/cert-manager/app/zerossl-eab-secret.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/external-dns/external-dns/app/external-dns-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/technitium/technitium/app/technitium-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/monitoring/victoria-logs-single/app/victoria-logs-single-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/monitoring/victoria-metrics-k8s-stack/app/victoria-metrics-k8s-stack-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/vaultwarden/vaultwarden/app/vaultwarden-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/vaultwarden/vaultwarden/app/vaultwarden-backup-secrets.sops.yaml"
sops --config "/workspaces/spruyt-labs/.sops.yaml" --encrypt --in-place "/workspaces/spruyt-labs/cluster/apps/cloudflare-system/cloudflared/app/cloudflared-secrets.sops.yaml"
