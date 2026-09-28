# coder-ssh-key-rotation - Coder Workspace SSH Key Rotation

## Overview

Rotates the SSH key Coder workspaces use for Git push and commit signing. Same image and flow as [bot-ssh-key-rotation](../bot-ssh-key-rotation/README.md), but every two days, with its own PAT and key title prefix (`coder-workspace`), patching `coder-ssh-signing-key` and force-syncing it into `coder-workspaces`.

## Prerequisites

- Classic PAT with `admin:public_key` and `admin:ssh_signing_key` in `app/coder-ssh-rotation-token.sops.yaml`. Not rotated automatically.
- In `coder-workspaces`: the `github-secret-store` SecretStore, the `coder-ssh-signing-key` ExternalSecret, and `github-rotation-rbac.yaml` (lets this job force-sync it). Read access for that store is granted here by `app/reader-role-binding-coder-workspaces.yaml`.

## Operations

### Kata grace period

Workspaces run under Kata, and virtiofs mounts are frozen at pod creation: a Secret update never reaches a running workspace. `GRACE_PERIOD_DAYS=8` keeps old keys valid on GitHub for four rotation cycles, so a workspace up to 8 days old can still push and sign. A workspace older than that loses Git access until it is restarted.

`CoderSSHKeyRotationConsecutiveFailures` fires after 5 days without a successful run, leaving 3 days to fix the job before the newest key ages out.

### Seed secret

`app/coder-ssh-signing-key.sops.yaml` carries `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` so Flux creates it once and never reverts the job's writes. Keep the annotation.

## References

- [GitHub SSH signing keys API](https://docs.github.com/en/rest/users/ssh-signing-keys)
