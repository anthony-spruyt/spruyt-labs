# n8n-mcp-server - n8n MCP Server

## Overview

MCP (Model Context Protocol) server providing AI assistants with access to n8n node documentation, workflow templates, validation, and workflow management via the n8n API. Runs in HTTP transport mode as a low-priority workload.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- n8n instance running in n8n-system namespace
- n8n API key with appropriate scopes (stored in SOPS secret)

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n n8n-mcp
flux get helmrelease -n flux-system n8n-mcp-server

# Force reconcile (GitOps approach)
flux reconcile kustomization n8n-mcp-server --with-source

# View logs
kubectl logs -n n8n-mcp -l app.kubernetes.io/name=n8n-mcp-server
```

## Access

- **In-cluster**: `http://n8n-mcp-server.n8n-mcp.svc:3000/mcp`
- **LAN**: `https://n8n-mcp.lan.${EXTERNAL_DOMAIN}/mcp` (API key required)
- **Health**: `GET /health`
- **Network policies**: Ingress from claude-agents-read, claude-agents-write, coder-workspaces, and traefik namespaces; egress to n8n.n8n-system.svc (port 80 → pod 5678)

## Troubleshooting

### Common Issues

1. **Pod fails to start**
   - **Symptom**: CrashLoopBackOff
   - **Resolution**: Check logs; likely missing or invalid N8N_API_KEY in n8n-mcp-secrets.

2. **Workflow management tools unavailable**
   - **Symptom**: MCP tool calls return errors for create/update/execute operations
   - **Resolution**: Verify N8N_API_KEY has required scopes and n8n API is reachable.

3. **Connection refused to n8n**
   - **Symptom**: MCP tools return connection errors
   - **Resolution**: Verify n8n pods are running in n8n-system and CiliumNetworkPolicy `allow-n8n-mcp-ingress` exists.

## References

- [n8n-mcp GitHub](https://github.com/czlonkowski/n8n-mcp)
- [n8n API docs](https://docs.n8n.io/api/)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
