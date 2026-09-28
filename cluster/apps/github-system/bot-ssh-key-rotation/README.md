# bot-ssh-key-rotation - Bot SSH Key Rotation

## Overview

Daily job that replaces the `spruyt-labs-bot` SSH key used by the write-tier Claude agents and every Coder workspace for Git push and commit signing. It registers a fresh ed25519 key on GitHub as both an auth and a signing key, deletes keys older than the grace period, patches `github-bot-ssh-key`, and force-syncs the consumers' ExternalSecrets. Consumer side:
[claude-agents-shared](../../claude-agents-shared/README.md).

## Prerequisites

- Classic PAT for the `spruyt-labs-bot` account with `admin:public_key` and `admin:ssh_signing_key`, stored as `GITHUB_PAT` in `app/bot-ssh-rotation-token.sops.yaml`. Fine-grained PATs and the GitHub App tokens cannot manage user keys. The PAT itself is not rotated - renew it before it expires.

## Operations

- The rotated secret is created by `github-token-rotation` (`github-bot-ssh-key.sops.yaml`) with `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent`, so Flux seeds it once and never overwrites the job's writes. Do not remove that annotation.
- `FORCE_SYNC_NAMESPACES` must list every namespace with a `github-bot-ssh-key` ExternalSecret. A namespace left out still gets the key, but only on its ExternalSecret `refreshInterval` or the next `github-token-rotation` run.
- The force-sync permission comes from `claude-agents-shared/base/github-rotation-rbac.yaml`, which binds this job's ServiceAccount in every agent namespace, and from `coder-workspaces/coder-workspaces/app/github-rotation-rbac.yaml` for the workspaces.
- `BotSSHKeyRotationFailed` / `BotSSHKeyRotationConsecutiveFailures` in `app/vmrule.yaml` alert on failures.

## References

- [GitHub SSH signing keys API](https://docs.github.com/en/rest/users/ssh-signing-keys)
- [GitHub user keys API](https://docs.github.com/en/rest/users/keys)
