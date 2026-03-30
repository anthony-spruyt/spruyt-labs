# claude-agents - Ephemeral Claude Code Agent Pods

## Overview

Provides ephemeral Claude Code agent pods spawned by n8n workflows. Each pod runs a `claude-agent` container that bootstraps configuration from the Kubernetes API, removes `kubectl` from its filesystem, then executes `claude -p` with the provided prompt and flags. Pods are short-lived and auto-deleted after the workflow completes.

Two ServiceAccounts are used:

- `claude-agent` — mounted on ephemeral pods; read-only access to ConfigMaps/Secrets in the `claude-agents` namespace
- `n8n-claude-spawner` — lives in `n8n-system`; creates and manages pods in `claude-agents`

## Prerequisites

- n8n deployed and operational (`n8n-system` namespace)
- `kubectl-mcp` MCP server available to agent pods
- `mcp-victoriametrics` MCP server available to agent pods

## Operation

### Pod Lifecycle

1. n8n workflow calls the `n8n-claude-spawner` SA to create a pod in `claude-agents`
2. Pod starts, bootstraps config from the K8s API (setup token, MCP config, Claude settings)
3. `kubectl` binary is removed from the pod filesystem
4. `claude -p` runs with the provided prompt
5. Pod exits; n8n deletes it via the spawner SA

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
kubectl logs -n claude-agents -l app.kubernetes.io/name=claude-agent
```

## Troubleshooting

### Common Issues

1. **Pod stuck in Pending**
   - **Symptom**: Pod shows `Pending` with no node assigned
   - **Resolution**: Check events with `kubectl get events -n claude-agents --sort-by='.lastTimestamp'`. Common causes are image pull failures (check image tag/registry credentials) or Pod Security Admission rejections (verify pod spec matches `restricted` policy)

2. **Auth failures (setup token expired or invalid)**
   - **Symptom**: Pod logs show authentication errors when bootstrapping config
   - **Resolution**: The setup token in `claude-credentials.sops.yaml` may be expired or rotated. Update the SOPS secret with a fresh token and let Flux reconcile. Check token expiry via Claude API console.

3. **MCP servers unreachable**
   - **Symptom**: Agent logs show MCP connection errors for `kubectl-mcp` or `mcp-victoriametrics`
   - **Resolution**: Inspect CiliumNetworkPolicies — egress rules on the `claude-agents` namespace must permit traffic to the MCP server endpoints. Run `kubectl get ciliumnetworkpolicy -n claude-agents` and verify egress selectors match the MCP pod labels/namespaces.

## References

- Spec document: `docs/claude-agents/` (implementation plan and architecture)
- GitHub issue: [#823](https://github.com/anthony-spruyt/spruyt-labs/issues/823)
