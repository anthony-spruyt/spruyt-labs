# Claude Agents Shared - Common Configuration Base

## Overview

Shared Kustomize base for `claude-agents-read` and `claude-agents-write` namespaces. Contains resources that are identical across both tiers: RBAC, network policies, MCP server config, GitHub bot credentials, and MCP API keys.

Each agent namespace references this base via its `kustomization.yaml` and only maintains tier-specific resources locally (e.g. `github-external-secret.yaml` for read vs write OAuth scopes).

## Structure

```text
claude-agents-shared/
  base/
    kustomization.yaml              # Resource list for the shared base
    claude-mcp-config.yaml          # MCP server endpoints and auth headers
    mcp-credentials.sops.yaml       # SOPS-encrypted API keys for MCP servers
    rbac.yaml                       # ServiceAccount for agent pods
    rbac-spawner.yaml               # Role/RoleBinding for n8n pod management
    network-policies.yaml           # CiliumNetworkPolicies for agent egress
    github-secret-store.yaml        # ESO SecretStore pointing to github-system
    github-ssh-external-secret.yaml # ESO ExternalSecret for SSH key
    github-bot-gitconfig.yaml       # Git config (signing, user identity)
    github-rotation-rbac.yaml       # RBAC for token rotation CronJob
```

## Adding a New MCP Server

### 1. Add the server entry to `base/claude-mcp-config.yaml`

For servers that don't need authentication:

```json
"my-server": {
  "type": "http",
  "url": "http://my-server.my-namespace.svc:8080/mcp"
}
```

For servers that need an API key:

```json
"my-server": {
  "baseUrl": "https://api.example.com/mcp",
  "headers": {
    "Authorization": "Bearer $${MY_SERVER_API_KEY}"
  }
}
```

The `$${}` syntax is replaced at runtime from pod environment variables.

### 2. Add API key to `base/mcp-credentials.sops.yaml` (if needed)

```bash
sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml
```

Add a new key:

```yaml
stringData:
  context7-api-key: "existing-key"
  ha-api-key: "existing-key"
  my-server-api-key: "new-key-here"  # add this
```

### 3. Add env var injection to Kyverno policy (if needed)

Edit `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` and add the env var to **both** rules (`inject-write-config` and `inject-read-config`):

```yaml
- name: MY_SERVER_API_KEY
  valueFrom:
    secretKeyRef:
      name: mcp-credentials
      key: my-server-api-key
```

### 4. Add network policy (if cluster-internal)

If the MCP server runs in-cluster, add a `CiliumNetworkPolicy` to `base/network-policies.yaml`:

```yaml
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-my-server-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: my-namespace
            k8s:app.kubernetes.io/name: my-server
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

External MCP servers (e.g. context7) are covered by the existing `allow-world-egress` policy.

## Per-Tier Overrides

Both tiers share the same base by default. To override a resource for one tier only (e.g. give write agents a different MCP config), add a patch in the tier's `kustomization.yaml`:

```yaml
# cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml
resources:
  - ../../../claude-agents-shared/base
  - ./github-external-secret.yaml
patches:
  - path: ./claude-mcp-config-patch.yaml
```

## Credential Rotation

| Secret | Rotation Method |
| ------ | --------------- |
| GitHub OAuth tokens | Automated via `github-token-rotation` CronJob |
| GitHub SSH key | Automated via `github-token-rotation` CronJob |
| MCP API keys | Manual: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml` |
| n8n SRE MCP auth token | Manual: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml` |

## Related Resources

| Resource | Location |
| -------- | -------- |
| Kyverno injection policy | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` |
| Read overlay | `cluster/apps/claude-agents-read/claude-agents/app/` |
| Write overlay | `cluster/apps/claude-agents-write/claude-agents/app/` |
| Read namespace | `cluster/apps/claude-agents-read/namespace.yaml` |
| Write namespace | `cluster/apps/claude-agents-write/namespace.yaml` |
