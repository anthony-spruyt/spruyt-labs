# github-token-rotation - GitHub App Installation Token Rotation

## Overview

CronJob that mints GitHub App installation tokens every 30 minutes. It generates a JWT from each App's private key, exchanges it for a short-lived installation token (`ghs_*`) via the GitHub API, patches the `github-bot-credentials` source secret in `github-system`, and force-syncs ESO ExternalSecrets in all consumer namespaces (`claude-agents-write`, `claude-agents-read`, `github-mcp`).

Installation tokens expire after 1 hour (fixed by GitHub). The 30-minute rotation schedule provides a safety margin. Unlike the previous OAuth refresh token design, this flow is **stateless** — each run generates tokens from scratch using only the static App private key. If a run fails, the next run self-heals with no manual intervention.

## Prerequisites

- Kubernetes cluster with Flux CD
- SOPS/Age decryption secret (`sops-age`) in `flux-system`
- SOPS-encrypted secrets in `github-system`:
  - `github-app-credentials` — App ID, Installation ID, and PEM private key for both write and read apps
  - `github-bot-credentials` — target secret for rotated tokens (created/maintained by CronJob)
  - `github-bot-ssh-key` — SSH signing key for verified commits
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
kubectl get externalsecret -n github-mcp
```

## Troubleshooting

### Common Issues

1. **JWT signing failure**
   - **Symptom**: Job logs show `openssl` errors during JWT generation.
   - **Resolution**: Verify the PEM private key in `github-app-credentials` is valid. Check that the App ID matches the key.

2. **Installation token mint fails with 401**
   - **Symptom**: `curl` returns 401 when calling the installations endpoint.
   - **Resolution**: JWT may be malformed or the App private key was rotated in GitHub. Regenerate the key in GitHub App settings and update the SOPS secret.

3. **Installation token mint fails with 404**
   - **Symptom**: `curl` returns 404 for the installations endpoint.
   - **Resolution**: The installation ID is wrong or the App was uninstalled. Verify at `https://github.com/settings/installations`.

4. **ESO sync not propagating after rotation**
   - **Symptom**: Consumer pods still use old tokens after a successful rotation job.
   - **Resolution**: The job force-syncs ExternalSecrets automatically. If it still fails, check SecretStore connectivity:
     ```bash
     kubectl get secretstore github-secret-store -n claude-agents-write
     kubectl describe secretstore github-secret-store -n claude-agents-write
     ```

5. **CronJob pod stuck or failing**
   - **Symptom**: Job pod in `Error` or `OOMKilled` state.
   - **Resolution**: Check pod logs and events:
     ```bash
     kubectl describe pod -n github-system -l app=github-token-rotation
     kubectl get events -n github-system --sort-by='.lastTimestamp'
     ```

## References

- [GitHub App installation tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
- [Generating a JWT for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)
- [External Secrets Operator - Kubernetes SecretStore](https://external-secrets.io/latest/provider/kubernetes/)
- [Flux Kustomization decryption (SOPS)](https://fluxcd.io/flux/guides/mozilla-sops/)
