# bot-ssh-key-rotation — Bot SSH signing key rotation

## Overview

Weekly CronJob that rotates the `github-bot-ssh-key` Secret used by `claude-agents-write` for Git SSH transport and commit signing. Generates a new ed25519 keypair, registers it on the `spruyt-labs-bot` GitHub account (auth + signing), cleans up old keys, patches the Kubernetes secret, and force-syncs ExternalSecrets in consumer namespaces.

> **Note**: No HelmRelease — this is a Kustomize-only component.

## Prerequisites

- `github-token-rotation` Kustomization deployed (dependsOn) — provides the `github-bot-ssh-key` Secret the CronJob patches.
- Image `ghcr.io/anthony-spruyt/ssh-key-rotation:2.0.0` published.
- Classic PAT for `spruyt-labs-bot` with `admin:public_key` + `admin:ssh_signing_key` scopes stored in `bot-ssh-rotation-token` SOPS secret.

## Troubleshooting

1. **Job fails patching Secret**

   - **Symptom**: `secrets "github-bot-ssh-key" forbidden`.
   - **Resolution**: Verify the `bot-ssh-key-rotation` Role grants `get, patch` on that Secret and the RoleBinding targets the ServiceAccount.

1. **NetworkPolicy drops egress**

   - **Symptom**: Job logs `connection refused` to kube-apiserver or GitHub.
   - **Resolution**: Egress CNPs live in `app/network-policies.yaml`. Confirm the pod label `app: bot-ssh-key-rotation` still matches.

1. **ExternalSecret force-sync fails**

   - **Symptom**: `externalsecrets "github-bot-ssh-key" forbidden` in logs.
   - **Resolution**: Check `github-rotation-rbac.yaml` in `claude-agents-shared/base/` includes `bot-ssh-key-rotation` SA as subject. Non-fatal — ExternalSecret `refreshInterval` will recover.

## References

- [GitHub SSH signing keys API](https://docs.github.com/en/rest/users/ssh-signing-keys)
- [GitHub user keys API](https://docs.github.com/en/rest/users/keys)
