# github-mcp-server - GitHub MCP Server

## Overview

GitHub MCP (Model Context Protocol) server that provides GitHub API access to Claude agents. It uses a read-tier GitHub App installation token for all API operations (issues, PRs, code search, repository contents). The server uses a two-container architecture: the `app` container (github-mcp-server) runs on port 8083, while a `auth-proxy` container (Caddy) handles API key authentication and exposes port 8082 via the Kubernetes Service. Accessible only to permitted workloads via Cilium network policies.

The read-tier token is synced from `github-system` by an ESO ExternalSecret and refreshed whenever `github-token-rotation` runs.

> **Note**: The HelmRelease is managed by Flux in the `flux-system` namespace but deploys workloads to the `github-mcp` namespace as specified in `ks.yaml`.

## Prerequisites

- Kubernetes cluster with Flux CD
- `github-token-rotation` Kustomization (provides the `github-bot-credentials` source secret)
- External Secrets Operator (`external-secrets` Kustomization)

## Operation

### Key Commands

```bash
# Check deployment and pod status
kubectl get pods -n github-mcp
flux get helmrelease -n github-mcp github-mcp-server

# Force reconcile
flux reconcile kustomization github-mcp-server --with-source

# View application logs
kubectl logs -n github-mcp -l app.kubernetes.io/name=github-mcp-server

# Verify ESO ExternalSecret is synced
kubectl get externalsecret github-bot-credentials -n github-mcp
kubectl describe externalsecret github-bot-credentials -n github-mcp

# Check the SecretStore connectivity
kubectl get secretstore github-secret-store -n github-mcp
kubectl describe secretstore github-secret-store -n github-mcp
```

### Verifying the Server is Reachable

```bash
# From a pod in an allowed namespace, test connectivity
kubectl run -it --rm debug --image=alpine --restart=Never -- \
  wget -qO- http://github-mcp-server.github-mcp.svc.cluster.local:8082/
```

## Troubleshooting

### Common Issues

1. **Pod in CrashLoopBackOff**
   - **Symptom**: Pod repeatedly crashes on startup.
   - **Resolution**: Check pod logs and verify the token secret is present:
     ```bash
     kubectl logs -n github-mcp -l app.kubernetes.io/name=github-mcp-server --previous
     kubectl get secret github-mcp-credentials -n github-mcp
     ```

2. **Connection refused / service unreachable**
   - **Symptom**: Clients get connection refused on port 8082.
   - **Resolution**: Verify the pod is Running and the service exists. Check CNPs are not blocking traffic:
     ```bash
     kubectl get svc -n github-mcp
     kubectl get ciliumnetworkpolicy -n github-mcp
     ```

3. **401 Unauthorized from GitHub API**
   - **Symptom**: Server logs show 401 errors when calling GitHub API.
   - **Resolution**: The read-tier token has expired. Trigger a manual token rotation:
     ```bash
     kubectl create job --from=cronjob/github-token-rotation \
       -n github-system github-token-rotation-manual
     ```
     Then force the ExternalSecret to re-sync:
     ```bash
     kubectl annotate externalsecret github-bot-credentials \
       -n github-mcp force-sync="$(date +%s)" --overwrite
     ```

4. **ESO sync failing**
   - **Symptom**: `kubectl get externalsecret github-bot-credentials -n github-mcp` shows `SecretSyncedError`.
   - **Resolution**: Check SecretStore RBAC and verify the source secret exists in `github-system`:
     ```bash
     kubectl get secret github-bot-credentials -n github-system
     kubectl describe secretstore github-secret-store -n github-mcp
     ```

## References

- [github/github-mcp-server](https://github.com/github/github-mcp-server)
- [External Secrets Operator - Kubernetes SecretStore](https://external-secrets.io/latest/provider/kubernetes/)
- [bjw-s app-template Helm chart](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
