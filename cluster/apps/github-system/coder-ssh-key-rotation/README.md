# coder-ssh-key-rotation — Coder SSH signing key rotation

## Overview

CronJob (every 2 days, `0 3 */2 * *`) that rotates the `coder-ssh-signing-key` Secret used by Coder workspaces for Git SSH transport and commit signing. Generates a new ed25519 keypair, registers it on GitHub (auth + signing), cleans up old keys, patches the Secret in `github-system`, and force-syncs the `coder-ssh-signing-key` ExternalSecret in `coder-workspaces`.

> **Note**: No HelmRelease — this is a Kustomize-only component.

## Prerequisites

- Image `ghcr.io/anthony-spruyt/ssh-key-rotation` published.
- Classic PAT with `admin:public_key` + `admin:ssh_signing_key` scopes stored in `coder-ssh-rotation-token` SOPS secret.
- `coder-workspaces` Kustomization provides the `github-secret-store` SecretStore, the `coder-ssh-signing-key` ExternalSecret, and the Role that lets this job force-sync it.

## Kata VM grace period

Kata virtiofs mounts are frozen at pod creation — Kubernetes secret volume updates do NOT propagate into the guest. `GRACE_PERIOD_DAYS=8` keeps old keys valid on GitHub for 8 days (four 2-day rotation cycles), so workspaces up to 8 days old continue signing/pushing. `CoderSSHKeyRotationConsecutiveFailures` fires after 5 days so there is time to fix the job before keys expire.

## Troubleshooting

1. **Job fails patching Secret**

   - **Symptom**: `secrets "coder-ssh-signing-key" forbidden`.
   - **Resolution**: Verify the `coder-ssh-key-rotation` Role grants `get, patch` on that Secret and the RoleBinding targets the ServiceAccount.

2. **NetworkPolicy drops egress**

   - **Symptom**: Job logs `connection refused` to kube-apiserver or GitHub.
   - **Resolution**: Egress CNPs live in `app/network-policies.yaml`. Confirm the pod label `app: coder-ssh-key-rotation` still matches.

3. **ExternalSecret force-sync fails**

   - **Symptom**: `externalsecrets "coder-ssh-signing-key" forbidden` in logs.
   - **Resolution**: Check `github-rotation-rbac.yaml` in `coder-workspaces/coder-workspaces/app/` binds the `coder-ssh-key-rotation` SA. Non-fatal — ExternalSecret `refreshInterval` will recover.

4. **ExternalSecret not syncing**

   - **Symptom**: `coder-ssh-signing-key` ExternalSecret in `coder-workspaces` is not `SecretSynced`.
   - **Resolution**: Check `app/reader-role-binding-coder-workspaces.yaml` binds `coder-workspaces/github-secret-reader` to the `coder-ssh-signing-key-reader` Role.

## References

- [GitHub SSH signing keys API](https://docs.github.com/en/rest/users/ssh-signing-keys)
- [GitHub user keys API](https://docs.github.com/en/rest/users/keys)
