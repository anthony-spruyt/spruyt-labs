# claude-agents-write - Write-Tier Claude Agent Namespace

## Overview

Namespace for write-tier Claude agent pods spawned ephemerally by n8n. Agents in this namespace are granted write-scoped GitHub credentials (code push, PR create) via an ESO ExternalSecret that syncs `write-hosts.yml` from `github-system`. An SSH deploy key is also synced for git operations over SSH.

The namespace contains no persistent workloads. Pods are created on demand by n8n using the spawner ServiceAccount and are automatically garbage-collected after completion. Credentials are injected via the `github-bot-credentials` and `github-bot-ssh-key` secrets, which are kept current by the `github-token-rotation` CronJob running in `github-system`.

## Prerequisites

- Kubernetes cluster with Flux CD
- `github-token-rotation` Kustomization (provides the `github-bot-credentials` source secret in `github-system`)
- External Secrets Operator (`external-secrets` Kustomization)

## Operation

### Key Commands

```bash
# Check namespace and any running agent pods
kubectl get pods -n claude-agents-write

# Verify ESO ExternalSecrets are synced
kubectl get externalsecret -n claude-agents-write
kubectl describe externalsecret github-bot-credentials -n claude-agents-write
kubectl describe externalsecret github-bot-ssh-key -n claude-agents-write

# Check SecretStore connectivity
kubectl get secretstore github-secret-store -n claude-agents-write
kubectl describe secretstore github-secret-store -n claude-agents-write

# Force Flux reconcile
flux reconcile kustomization claude-agents-write --with-source

# Check Kyverno ClusterPolicy audit results (credential injection policy)
kubectl get policyreport -n claude-agents-write
```

### Verifying RBAC for the Spawner

```bash
# Check that the n8n spawner ServiceAccount can create pods
kubectl auth can-i create pods -n claude-agents-write \
  --as=system:serviceaccount:n8n-system:n8n
```

## Troubleshooting

### Common Issues

1. **Agent pod cannot push to GitHub**
   - **Symptom**: Agent pod exits with `Permission denied` or authentication failure when running `git push`.
   - **Resolution**: Verify the write-tier credentials are injected and current:
     ```bash
     kubectl get secret github-bot-credentials -n claude-agents-write
     kubectl get externalsecret github-bot-credentials -n claude-agents-write
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
     kubectl describe secretstore github-secret-store -n claude-agents-write
     ```

3. **Pod creation denied**
   - **Symptom**: n8n cannot spawn agent pods; events show `Forbidden`.
   - **Resolution**: Check RBAC for the spawner role:
     ```bash
     kubectl get rolebinding -n claude-agents-write
     kubectl describe rolebinding -n claude-agents-write
     ```

4. **Network policy blocking egress**
   - **Symptom**: Agent pod cannot reach GitHub API or git remotes.
   - **Resolution**: Review the CNPs in the namespace:
     ```bash
     kubectl get ciliumnetworkpolicy -n claude-agents-write
     ```

## References

- [External Secrets Operator - Kubernetes SecretStore](https://external-secrets.io/latest/provider/kubernetes/)
- [Kyverno Policy Documentation](https://kyverno.io/docs/)
- [GitHub App Installation Tokens](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-an-installation-access-token-for-a-github-app)
