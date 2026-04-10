# Discord MCP - Discord API MCP Server

## Overview

Discord MCP server providing AI agents with Discord API access via the Model Context Protocol. Uses [barryyip0625/mcp-discord](https://github.com/barryyip0625/mcp-discord) which serves native Streamable HTTP on port 8080.

Available tools include reading/sending messages, managing channels, forums, webhooks, categories, and reactions.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- `discord-secrets` SOPS secret containing `DISCORD_TOKEN`
- Discord bot invited to target server with Message Content Intent enabled

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n discord-mcp
flux get helmrelease -n flux-system discord-mcp

# Force reconcile (GitOps approach)
flux reconcile kustomization discord-mcp --with-source

# View logs
kubectl logs -n discord-mcp -l app.kubernetes.io/name=discord-mcp
```

## Troubleshooting

### Common Issues

1. **Pod fails to start / Discord login errors**
   - **Symptom**: Pod logs show "Discord login failed" or intent errors
   - **Resolution**: Verify bot token is valid and Message Content Intent is enabled in the Discord Developer Portal

2. **MCP connection timeout from agent pods**
   - **Symptom**: Agent reports discord MCP server unavailable
   - **Resolution**: Check network policies allow ingress from `claude-agents-read`, `claude-agents-write`, and `coder-system` namespaces on port 8080

## References

- [mcp-discord GitHub](https://github.com/barryyip0625/mcp-discord)
- [Docker Hub](https://hub.docker.com/r/barryy625/mcp-discord)
