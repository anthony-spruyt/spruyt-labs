# ssh-key-rotation — Coder SSH signing key rotation

## Overview

Weekly CronJob that rotates the `coder-ssh-signing-key` Secret used by Coder workspaces for Git SSH auth. Formerly colocated under `coder/app/`; relocated to its own top-level app (parallels `coder-template-sync/`) so it has an independent Flux Kustomization and lifecycle.

> **Note**: No HelmRelease — this is a Kustomize-only component.

## Prerequisites

- `coder` Kustomization deployed (dependsOn) — provides the `coder-ssh-signing-key` Secret the CronJob patches.
- Image `ghcr.io/anthony-spruyt/ssh-key-rotation` published.

## Troubleshooting

1. **Job fails patching Secret**

   - **Symptom**: `secrets "coder-ssh-signing-key" forbidden`.
   - **Resolution**: Verify the `ssh-key-rotation` Role grants `get, patch` on that Secret and the RoleBinding targets the ServiceAccount.

2. **NetworkPolicy drops egress**

   - **Symptom**: Job logs `connection refused` to kube-apiserver or GitHub.
   - **Resolution**: Egress CNPs live in `app/network-policy.yaml` (`allow-ssh-rotation-*`). Confirm the pod label `app: ssh-key-rotation` still matches.

## Kata VM grace period

Kata virtiofs mounts are frozen at pod creation — Kubernetes secret volume updates do NOT propagate into the guest. `GRACE_PERIOD_DAYS=8` keeps the previous key valid on GitHub for one full rotation cycle (7 days) plus buffer, so workspaces that span a rotation boundary continue signing/pushing.

## References

- [Coder SSH keys](https://coder.com/docs/admin/external-auth)
