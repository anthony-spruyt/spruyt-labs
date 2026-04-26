# Claude Agents SRE - SRE Agent Execution Namespace

## Overview

Isolated namespace for Claude Code SRE agent pods spawned by n8n. SRE agents triage incidents and investigate cluster state but do not commit changes. Uses read-tier GitHub OAuth and high-priority scheduling to ensure availability during incidents.

> **Note**: Agent pods are created dynamically by n8n workflows, not by Flux HelmReleases.

## Prerequisites

- Kubernetes cluster with Flux CD
- github-token-rotation (provides GitHub bot credentials via ExternalSecret)

## Operation

### Key Commands

```bash
# Check running agent pods
kubectl get pods -n claude-agents-sre

# Check Flux kustomization status
flux get kustomization claude-agents-sre

# Force reconcile (GitOps approach)
flux reconcile kustomization claude-agents-sre --with-source

# View agent pod logs
kubectl logs -n claude-agents-sre -l managed-by=n8n-claude-code
```

## Troubleshooting

### Common Issues

1. **Agent pod stuck in Pending**

   - **Symptom**: Pod remains in Pending state
   - **Resolution**: Check node resources and priority class — SRE pods use `high-priority` (100000)

1. **MCP server connection failures**

   - **Symptom**: Agent cannot reach MCP servers
   - **Resolution**: Verify CiliumNetworkPolicies allow egress to target MCP namespace/port

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
