# claude-agents - Ephemeral Claude Code Agent Pods

## Overview

Provides the namespace and RBAC for ephemeral Claude Code agent pods spawned by n8n workflows via the `n8n-nodes-claude-code-cli` community node. Pods are short-lived and auto-deleted after the workflow completes.

- `claude-agent` SA — assigned to ephemeral pods
- n8n's own SA — bound to `claude-pod-manager` Role for pod lifecycle management (in-cluster auth)

Auth, MCP config, and settings are handled by the community node and baked into the container image — no K8s secrets or configmaps needed.

## Prerequisites

- n8n deployed and operational (`n8n-system` namespace)
- `kubectl-mcp` MCP server available to agent pods
- `mcp-victoriametrics` MCP server available to agent pods
- Community node `n8n-nodes-claude-code-cli` installed in n8n

## Operation

### Pod Lifecycle

1. n8n workflow triggers the Claude Code node
2. Community node creates an ephemeral pod in `claude-agents` using n8n's in-cluster SA
3. Pod runs `claude -p` with the configured prompt and MCP servers
4. Pod exits; community node deletes it

### Key Commands

```bash
# Check running agent pods
kubectl get pods -n claude-agents

# Check Flux kustomization status
flux get kustomization claude-agents -n flux-system

# Force reconcile
flux reconcile kustomization claude-agents --with-source

# View logs for an agent pod
kubectl logs -n claude-agents <pod-name>

# View logs for all agent pods (label selector)
kubectl logs -n claude-agents -l managed-by=n8n-claude-code
```

## Troubleshooting

### Common Issues

1. **Pod stuck in Pending**
   - **Symptom**: Pod shows `Pending` with no node assigned
   - **Resolution**: Check events with `kubectl get events -n claude-agents --sort-by='.lastTimestamp'`. Common causes are image pull failures (check image tag/registry) or Pod Security Admission rejections (image must use numeric UID)

2. **Auth failures (Not logged in)**
   - **Symptom**: Pod logs show "Not logged in" or authentication errors
   - **Resolution**: Check the `CLAUDE_CODE_OAUTH_TOKEN` environment variable in the n8n credential's Environment Variables field. Setup tokens expire after 1 year.

3. **MCP servers unreachable**
   - **Symptom**: Agent reports no MCP tools available
   - **Resolution**: Verify MCP config is baked into the image (`/workspace/.mcp.json`). Check CiliumNetworkPolicies allow egress from `claude-agents` to MCP server endpoints. CNP selectors must match `managed-by: n8n-claude-code` label.

4. **Connection timeout creating pod**
   - **Symptom**: n8n node times out before pod is created
   - **Resolution**: Check n8n has kube-apiserver egress CNP (`allow-kube-api-egress` in n8n-system). Check Hubble/Grafana for CNP drops.

## References

- Spec: `docs/superpowers/specs/2026-03-30-n8n-claude-code-cli-phase1-design.md`
- Plan: `docs/superpowers/plans/2026-03-30-n8n-claude-code-cli-phase1.md`
- GitHub issue: [#823](https://github.com/anthony-spruyt/spruyt-labs/issues/823)
