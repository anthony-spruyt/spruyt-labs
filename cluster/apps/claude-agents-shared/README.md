# Claude Agents Shared - Common Configuration Base

## Overview

Shared Kustomize base for `claude-agents-read`, `claude-agents-write`, and `claude-agents-sre` namespaces. Contains resources that are identical across all tiers: RBAC, network policies, GitHub bot credentials, and MCP API keys.

Each agent namespace references this base via its `kustomization.yaml` and maintains tier-specific resources locally (e.g. MCP config, network policies, external secrets).

## Structure

```text
claude-agents-shared/
  base/
    kustomization.yaml              # Resource list
    mcp-credentials.sops.yaml       # SOPS-encrypted API keys for MCP servers
    rbac.yaml                       # ServiceAccount for agent pods
    rbac-spawner.yaml               # Role/RoleBinding for n8n pod management
    network-policies.yaml           # CiliumNetworkPolicies for agent egress
    github-secret-store.yaml        # ESO SecretStore pointing to github-system
    github-bot-gitconfig-read.yaml  # Read-only git config (user identity only, no signing)
    github-rotation-rbac.yaml       # RBAC for token rotation CronJob
```

MCP server configs and settings profiles are per-namespace (not in this base):

```text
claude-agents-read/claude-agents/app/claude-mcp-config-read.yaml
claude-agents-read/claude-agents/app/settings/read.json
claude-agents-read/claude-agents/app/settings/triage.json
claude-agents-write/claude-agents/app/claude-mcp-config-write.yaml
claude-agents-write/claude-agents/app/settings/execute.json
claude-agents-write/claude-agents/app/settings/fix.json
claude-agents-sre/claude-agents/app/claude-mcp-config-sre.yaml
claude-agents-sre/claude-agents/app/settings/sre.json
claude-agents-sre/claude-agents/app/settings/validate.json
```

## Settings Profiles

Each profile is a Claude Code `settings.json` for per-role configuration. MCP server access is controlled by per-namespace MCP configs (allowlist pattern), not by settings profiles.

Profiles are bundled into a per-namespace `claude-settings-profiles` ConfigMap via `configMapGenerator` and mounted at `/etc/claude/settings/` in all agent pods by the Kyverno injection policy.

### Usage in n8n

Set **Additional Arguments** on the Claude Code CLI node:

```text
--settings /etc/claude/settings/sre.json
```

### Adding a New Profile

1. Create a new JSON file in the target namespace's `settings/` directory:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json"
}
```

2. Add the file to `configMapGenerator.files` in the namespace's `kustomization.yaml`
1. Commit and push — new pods will pick up the profile automatically

## Adding a New MCP Server

### 1. Add the server entry to the relevant tier's MCP config

Edit the appropriate `claude-mcp-config-{read,write,sre}.yaml` in its namespace's `app/` directory.

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
  "type": "http",
  "url": "https://api.example.com/mcp",
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
  my-server-api-key: "new-key-here"  # add this
```

### 3. Add env var injection to Kyverno policy (if needed)

Edit `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` and add the env var to the appropriate tier rule(s):

```yaml
- name: MY_SERVER_API_KEY
  valueFrom:
    secretKeyRef:
      name: mcp-credentials
      key: my-server-api-key
```

### 4. Add network policy (if cluster-internal)

If the MCP server runs in-cluster, add a `CiliumNetworkPolicy` to `base/network-policies.yaml` (shared) or the tier's own `network-policies.yaml`:

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

## Credential Rotation

| Secret              | Rotation Method                                                                 |
| ------------------- | ------------------------------------------------------------------------------- |
| GitHub OAuth tokens | Automated via `github-token-rotation` CronJob                                   |
| GitHub SSH key      | Automated via `github-token-rotation` CronJob (write namespace only)            |
| MCP API keys        | Manual: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml` |

## Related Resources

| Resource                 | Location                                                            |
| ------------------------ | ------------------------------------------------------------------- |
| Kyverno injection policy | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` |
| Read overlay             | `cluster/apps/claude-agents-read/claude-agents/app/`                |
| Write overlay            | `cluster/apps/claude-agents-write/claude-agents/app/`               |
| SRE overlay              | `cluster/apps/claude-agents-sre/claude-agents/app/`                 |
| Read namespace           | `cluster/apps/claude-agents-read/namespace.yaml`                    |
| Write namespace          | `cluster/apps/claude-agents-write/namespace.yaml`                   |
| SRE namespace            | `cluster/apps/claude-agents-sre/namespace.yaml`                     |
