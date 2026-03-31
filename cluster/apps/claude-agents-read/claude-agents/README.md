# claude-agents-read - Read-Tier Claude Agent Namespace

## Overview

Namespace for read-tier Claude agent pods spawned ephemerally by n8n. Agents in this namespace are granted read+comment-scoped GitHub credentials via an ESO ExternalSecret that syncs `read-hosts.yml` from `github-system`. An SSH deploy key is also synced for read-only git clone operations over SSH.

Agents in this namespace cannot push code or create PRs — the synced token is scoped to read and issue comment operations only. Pods are created on demand by n8n using the spawner ServiceAccount and are automatically garbage-collected after completion. Credentials are kept current by the `github-token-rotation` CronJob running in `github-system`.

## Prerequisites

- Kubernetes cluster with Flux CD
- `github-token-rotation` Kustomization (provides the `github-bot-credentials` source secret in `github-system`)
- External Secrets Operator (`external-secrets` Kustomization)

## Operation

### Key Commands

```bash
# Check namespace and any running agent pods
kubectl get pods -n claude-agents-read

# Verify ESO ExternalSecrets are synced
kubectl get externalsecret -n claude-agents-read
kubectl describe externalsecret github-bot-credentials -n claude-agents-read
kubectl describe externalsecret github-bot-ssh-key -n claude-agents-read

# Check SecretStore connectivity
kubectl get secretstore github-secret-store -n claude-agents-read
kubectl describe secretstore github-secret-store -n claude-agents-read

# Force Flux reconcile
flux reconcile kustomization claude-agents-read --with-source

# Check Kyverno ClusterPolicy audit results (credential injection policy)
kubectl get policyreport -n claude-agents-read
```

### Verifying RBAC for the Spawner

```bash
# Check that the n8n spawner ServiceAccount can create pods
kubectl auth can-i create pods -n claude-agents-read \
  --as=system:serviceaccount:n8n-system:n8n
```

## Troubleshooting

### Common Issues

1. **Agent pod cannot read from GitHub / 401 errors**
   - **Symptom**: Agent pod exits with authentication failure when accessing GitHub API or cloning a repo.
   - **Resolution**: Verify the read-tier credentials are injected and current:
     ```bash
     kubectl get secret github-bot-credentials -n claude-agents-read
     kubectl get externalsecret github-bot-credentials -n claude-agents-read
     ```
     If the ExternalSecret shows a sync error, trigger manual token rotation:
     ```bash
     kubectl create job --from=cronjob/github-token-rotation \
       -n github-system github-token-rotation-manual
     ```

2. **ESO sync failing**
   - **Symptom**: ExternalSecret status shows `SecretSyncedError` or `NoSecretError`.
   - **Resolution**: Verify the source secret exists in `github-system` and the SecretStore RBAC is correct:
     ```bash
     kubectl get secret github-bot-credentials -n github-system
     kubectl describe secretstore github-secret-store -n claude-agents-read
     ```

3. **Pod creation denied**
   - **Symptom**: n8n cannot spawn agent pods; events show `Forbidden`.
   - **Resolution**: Check RBAC for the spawner role:
     ```bash
     kubectl get rolebinding -n claude-agents-read
     kubectl describe rolebinding -n claude-agents-read
     ```

4. **Network policy blocking egress**
   - **Symptom**: Agent pod cannot reach GitHub API or git remotes.
   - **Resolution**: Review the CNPs in the namespace:
     ```bash
     kubectl get ciliumnetworkpolicy -n claude-agents-read
     ```

## References

- [External Secrets Operator - Kubernetes SecretStore](https://external-secrets.io/latest/provider/kubernetes/)
- [Kyverno Policy Documentation](https://kyverno.io/docs/)
- [GitHub App OAuth - User Access Tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)
