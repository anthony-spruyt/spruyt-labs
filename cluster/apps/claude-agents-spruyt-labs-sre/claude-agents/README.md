# claude-agents-spruyt-labs-sre - SRE-Tier Claude Agent Namespace

## Overview

Namespace for SRE-tier Claude agent pods spawned ephemerally by n8n during incident response. Agents in this namespace triage incidents and investigate cluster state but do not commit code. They run with `priorityClassName: high-priority` (100000) to ensure availability under pressure.

Agents are granted read-tier GitHub credentials via an ESO ExternalSecret that syncs `read-hosts.yml` from `github-system` — SRE agents inspect repos but never push. Pods are created on demand by n8n using the spawner ServiceAccount and are automatically garbage-collected after completion. Credentials are kept current by the `github-token-rotation` CronJob running in `github-system`.

> **Note**: Agent pods are created dynamically by n8n workflows, not by Flux HelmReleases. The namespace contains only infra (ExternalSecret, CNPs, RBAC from shared base, encrypted SRE credentials).

## Prerequisites

- Kubernetes cluster with Flux CD
- `github-token-rotation` Kustomization (provides the `github-bot-credentials` source secret in `github-system`)
- External Secrets Operator (`external-secrets` Kustomization)
- `github-secret-store` SecretStore (created in `claude-agents-shared/base`, mounted via kustomization base reference)
- PriorityClass `high-priority` (defined in `cluster/flux/meta/priority-classes.yaml`)

## Operation

### Key Commands

```bash
# Check namespace and any running agent pods
kubectl get pods -n claude-agents-spruyt-labs-sre

# Verify ESO ExternalSecrets are synced
kubectl get externalsecret -n claude-agents-spruyt-labs-sre
kubectl describe externalsecret github-bot-credentials -n claude-agents-spruyt-labs-sre

# Check SecretStore connectivity
kubectl get secretstore github-secret-store -n claude-agents-spruyt-labs-sre
kubectl describe secretstore github-secret-store -n claude-agents-spruyt-labs-sre

# Force Flux reconcile
flux reconcile kustomization claude-agents-spruyt-labs-sre --with-source

# Check Kyverno ClusterPolicy audit results
kubectl get policyreport -n claude-agents-spruyt-labs-sre

# View agent pod logs
kubectl logs -n claude-agents-spruyt-labs-sre -l managed-by=n8n-claude-code
```

### Verifying RBAC for the Spawner

```bash
# Check that the n8n spawner ServiceAccount can create pods
kubectl auth can-i create pods -n claude-agents-spruyt-labs-sre \
  --as=system:serviceaccount:n8n-system:n8n
```

## Troubleshooting

### Common Issues

1. **Agent pod stuck in Pending**

   - **Symptom**: Pod remains in Pending state.
   - **Resolution**: Check node resources and that the `high-priority` PriorityClass exists. Priority is set on the spawned pod by Kyverno (`inject-sre-mcp` rule), not on the namespace itself:
     ```bash
     kubectl get priorityclass high-priority
     kubectl describe pod <pod> -n claude-agents-spruyt-labs-sre
     ```

1. **Agent pod cannot read from GitHub / 401 errors**

   - **Symptom**: Agent pod exits with authentication failure when accessing GitHub API.
   - **Resolution**: Verify the read-tier credentials are injected and current:
     ```bash
     kubectl get secret github-bot-credentials -n claude-agents-spruyt-labs-sre
     kubectl get externalsecret github-bot-credentials -n claude-agents-spruyt-labs-sre
     ```
     If the ExternalSecret shows a sync error, trigger manual token rotation:
     ```bash
     kubectl create job --from=cronjob/github-token-rotation \
       -n github-system github-token-rotation-manual
     ```

1. **ESO sync failing**

   - **Symptom**: ExternalSecret status shows `SecretSyncedError` or `NoSecretError`.
   - **Resolution**: Verify the source secret exists in `github-system` and the SecretStore RBAC is correct:
     ```bash
     kubectl get secret github-bot-credentials -n github-system
     kubectl describe secretstore github-secret-store -n claude-agents-spruyt-labs-sre
     ```

1. **MCP server connection failures**

   - **Symptom**: Agent cannot reach kubectl/discord/victoriametrics/n8n MCP servers.
   - **Resolution**: Verify the per-namespace egress CNPs and the corresponding ingress on each MCP server include `claude-agents-spruyt-labs-sre`:
     ```bash
     kubectl get ciliumnetworkpolicy -n claude-agents-spruyt-labs-sre
     ```

1. **Pod creation denied**

   - **Symptom**: n8n cannot spawn agent pods; events show `Forbidden`.
   - **Resolution**: Check RBAC for the spawner role:
     ```bash
     kubectl get rolebinding -n claude-agents-spruyt-labs-sre
     kubectl describe rolebinding -n claude-agents-spruyt-labs-sre
     ```

## References

- [External Secrets Operator - Kubernetes SecretStore](https://external-secrets.io/latest/provider/kubernetes/)
- [Kyverno Policy Documentation](https://kyverno.io/docs/)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
