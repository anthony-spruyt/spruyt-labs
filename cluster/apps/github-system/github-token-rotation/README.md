# github-token-rotation - GitHub App OAuth Token Rotation

## Overview

CronJob that rotates GitHub App OAuth tokens every 4 hours. It refreshes both the write-tier (code push, PR create) and read-tier (API read, issue comment) access tokens, patches the `github-bot-credentials` source secret in `github-system`, and force-syncs the ESO ExternalSecrets in all consumer namespaces (`claude-agents-write`, `claude-agents-read`, `openclaw`, `github-mcp`).

Tokens are short-lived GitHub App OAuth access tokens backed by longer-lived refresh tokens. If a refresh token expires (GitHub App OAuth refresh tokens expire after 6 months of inactivity), a full re-authorization via the GitHub App OAuth flow is required.

## Prerequisites

- Kubernetes cluster with Flux CD
- SOPS/Age decryption secret (`sops-age`) in `flux-system`
- SOPS-encrypted secrets in `github-system`:
  - `github-app-credentials` — write and read app client ID + client secret
  - `github-bot-credentials` — current write and read access + refresh tokens
  - `github-bot-ssh-key` — SSH deploy key for git operations
- External Secrets Operator (`external-secrets` Kustomization)

## Operation

### Key Commands

```bash
# Check CronJob and recent job history
kubectl get cronjob github-token-rotation -n github-system
kubectl get jobs -n github-system

# View logs from the most recent job pod
kubectl logs -n github-system -l app=github-token-rotation --tail=100

# Trigger manual rotation immediately
kubectl create job --from=cronjob/github-token-rotation \
  -n github-system github-token-rotation-manual

# Force Flux reconcile
flux reconcile kustomization github-token-rotation --with-source

# Verify ESO ExternalSecrets synced in consumer namespaces
kubectl get externalsecret -n claude-agents-write
kubectl get externalsecret -n claude-agents-read
kubectl get externalsecret -n openclaw
kubectl get externalsecret -n github-mcp
```

### Re-authorization Procedure

If refresh tokens have expired (error: `bad_refresh_token` or `expired_token` in job logs):

1. Re-authorize each GitHub App via the OAuth flow to obtain new access and refresh tokens.
2. Update the SOPS-encrypted `github-bot-credentials` secret with the new tokens.
3. Push the updated secret and let Flux decrypt and apply it.
4. Trigger a manual rotation to verify the new tokens work.

## Troubleshooting

### Common Issues

1. **Token not refreshing / job fails with `bad_refresh_token`**
   - **Symptom**: Job pod logs show `ERROR: Failed to parse tokens from response` or a GitHub error about an invalid/expired refresh token.
   - **Resolution**: Refresh tokens have expired. Follow the Re-authorization Procedure above.

2. **ESO sync not propagating after rotation**
   - **Symptom**: Consumer pods still use old tokens after a successful rotation job.
   - **Resolution**: The job force-syncs ExternalSecrets automatically. If it still fails, check the SecretStore connectivity:
     ```bash
     kubectl get secretstore github-secret-store -n claude-agents-write
     kubectl describe secretstore github-secret-store -n claude-agents-write
     ```

3. **CronJob pod stuck or failing**
   - **Symptom**: Job pod in `Error` or `OOMKilled` state.
   - **Resolution**: Check pod logs and events:
     ```bash
     kubectl describe pod -n github-system -l app=github-token-rotation
     kubectl get events -n github-system --sort-by='.lastTimestamp'
     ```

4. **SOPS secrets not found**
   - **Symptom**: Pod fails with `secret "github-app-credentials" not found` or similar.
   - **Resolution**: Verify that the SOPS-encrypted secrets are applied and Flux has decrypted them:
     ```bash
     kubectl get secret github-app-credentials -n github-system
     kubectl get secret github-bot-credentials -n github-system
     flux get kustomization github-token-rotation
     ```

## References

- [GitHub App OAuth token refresh](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)
- [External Secrets Operator - Kubernetes SecretStore](https://external-secrets.io/latest/provider/kubernetes/)
- [Flux Kustomization decryption (SOPS)](https://fluxcd.io/flux/guides/mozilla-sops/)
