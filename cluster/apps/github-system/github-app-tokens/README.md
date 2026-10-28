# github-app-tokens - GitHub App Installation Tokens

## Overview

Two External Secrets `GithubAccessToken` generators mint installation tokens for a write App and a read App from their private keys. The ExternalSecret `github-bot-credentials` renders them into the Secret of the same name and refreshes every 30 minutes; installation tokens live 60 minutes, so one refresh can fail without an outage. Consumer namespaces pull the Secret every 5 minutes through their
own SecretStore. Each refresh starts from the App private key, so a failed refresh heals on the next one.

## Prerequisites

- Two GitHub Apps installed on the target repositories. App ID, installation ID and PEM private key for each are in `app/github-app-credentials.sops.yaml` as `write-app-id`, `write-installation-id`, `write-private-key` and the `read-*` equivalents.

## Operations

### Secrets in this directory

| Secret                   | Written by                                                | Notes                                                                    |
| ------------------------ | --------------------------------------------------------- | ------------------------------------------------------------------------ |
| `github-app-credentials` | You (SOPS)                                                | Only secret here that needs manual rotation                              |
| `github-bot-credentials` | ExternalSecret `github-bot-credentials`                   | `<write\|read>-access-token`, `<write\|read>-hosts.yml`                  |
| `github-bot-ssh-key`     | [bot-ssh-key-rotation](../bot-ssh-key-rotation/README.md) | Not managed here; the `github-token-reader` Role grants consumers access |

### Adding a consumer namespace

1. In the consumer: a `SecretStore` pointing at `github-system` and an `ExternalSecret` for `github-bot-credentials` (see `claude-agents-shared/base/github-secret-store.yaml`).
2. Here: a `reader-role-binding-<ns>.yaml` binding the consumer's reader ServiceAccount to the `github-token-reader` Role in `reader-role.yaml` (`litellm` has its own `reader-role-litellm.yaml`, limited to `github-bot-credentials`), listed in `app/kustomization.yaml`.

### Rotating an App private key

Generate a new key in the GitHub App settings and replace it in `github-app-credentials` with `sops`. Delete the old key in GitHub once the next refresh has succeeded.

## Troubleshooting

1. **ExternalSecret `github-bot-credentials` not Ready**
   - **Cause**: A generator call failed; the status message carries the GitHub error. Consumers keep the last token until it expires. `GitHubAppTokensRefreshFailing` fires after 5 minutes and `GitHubAppTokensExpiring` after 20.
   - **Fix**: See the entries below.
2. **401 from GitHub**
   - **Cause**: The App private key was revoked or does not match the App ID.
   - **Fix**: Put the current key in `github-app-credentials`.
3. **404 from GitHub**
   - **Cause**: Wrong installation ID, or the App was uninstalled.
   - **Fix**: Correct the installation ID in `github-app-credentials`, or reinstall the App.
4. **Timeout reaching `api.github.com`**
   - **Cause**: Only the External Secrets controller calls GitHub, and its egress is allowed by `allow-controller-github-egress` in `cluster/apps/external-secrets/network-policies.yaml`.
   - **Fix**: Restore that policy.

## References

- [GitHub App installation tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [External Secrets GitHub generator](https://external-secrets.io/latest/api/generator/github/)
