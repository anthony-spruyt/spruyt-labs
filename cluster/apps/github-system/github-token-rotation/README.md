# github-token-rotation - GitHub App Installation Tokens

## Overview

Every 30 minutes, mints installation tokens for two GitHub Apps (a write app and a read app) from their private keys, writes them into `github-bot-credentials`, and force-syncs the ExternalSecrets in the Claude agent namespaces and `n8n-system`. Installation tokens live one hour, so the schedule leaves one retry of headroom. The flow is stateless - each run starts from the App private key - so a
failed run heals on the next one.

## Prerequisites

- Two GitHub Apps installed on the target repositories. App ID, installation ID and PEM private key for each are in `app/github-app-credentials.sops.yaml` (`write-*` and `read-*` keys).

## Operations

### Secrets in this directory

| Secret                   | Written by                                                | Notes                                                          |
| ------------------------ | --------------------------------------------------------- | -------------------------------------------------------------- |
| `github-app-credentials` | You (SOPS)                                                | Only secret here that needs manual rotation                    |
| `github-bot-credentials` | This job                                                  | `<write\|read>-access-token`, `-hosts.yml`, `-git-credentials` |
| `github-bot-ssh-key`     | [bot-ssh-key-rotation](../bot-ssh-key-rotation/README.md) | Lives here so both jobs share the reader RBAC                  |

`github-bot-credentials` and `github-bot-ssh-key` carry `kustomize.toolkit.fluxcd.io/ssa: IfNotPresent`: Flux seeds them once and never reverts the rotated values. Removing the annotation makes every Flux reconcile roll the tokens back to the stale SOPS copy.

### Adding a consumer namespace

1. In the consumer: a `SecretStore` pointing at `github-system` and an `ExternalSecret` for `github-bot-credentials` (see `claude-agents-shared/base/github-secret-store.yaml`).
2. Here: a `reader-role-binding-<ns>.yaml` binding the consumer's reader ServiceAccount to the `reader-role`.
3. Add the namespace to the `force_sync_consumers` loop in `app/cronjob.yaml`, and grant this job's ServiceAccount `get, patch` on the ExternalSecret in that namespace (see `n8n-system/n8n/app/github-rotation-rbac.yaml`). Without step 3 the consumer still converges, but only on its own `refreshInterval`.

### Rotating an App private key

Generate a new key in the GitHub App settings, replace it in `github-app-credentials` with `sops`, then delete the old key in GitHub once a run has succeeded.

## Troubleshooting

1. **401 from the installations endpoint** - the App private key was revoked or does not match the App ID.
2. **404 from the installations endpoint** - wrong installation ID, or the App was uninstalled.
3. **Job fails before minting** - it downloads `openssl` from the Alpine CDN at runtime (retried 3 times); a CDN or egress outage fails the run. The next run retries.

## References

- [GitHub App installation tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
