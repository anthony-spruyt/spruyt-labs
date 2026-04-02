# kubectl-mcp-server - Kubernetes MCP Server

## Overview

MCP (Model Context Protocol) server providing AI assistants with access to Kubernetes cluster resources. Primarily read-only with targeted write permissions for operational tasks. Deployed as a low-priority workload.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- No dependencies (self-contained with its own RBAC)

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n kubectl-mcp
flux get helmrelease -n flux-system kubectl-mcp-server

# Force reconcile (GitOps approach)
flux reconcile kustomization kubectl-mcp-server --with-source

# View logs
kubectl logs -n kubectl-mcp -l app.kubernetes.io/name=kubectl-mcp-server
```

## Access

- **Traefik ingress**: LAN-only via `kubectl-mcp.lan.${EXTERNAL_DOMAIN}`, requires `X-API-KEY` header
- **Network policies**: Ingress allowed from Traefik only; egress allowed to kube-apiserver only
- **RBAC scope**: Read-only access to most resources (including pod logs). Limited writes: pods (delete, eviction), deployments/statefulsets scale subresource only. Cordon/drain/taint/restart/job-creation fall back to local kubectl.

## Troubleshooting

### Common Issues

1. **Pod fails to start**
   - **Symptom**: CrashLoopBackOff
   - **Resolution**: Check logs; likely ServiceAccount or RBAC issue. Verify ClusterRole and ClusterRoleBinding exist.

2. **MCP tools return 403 errors**
   - **Symptom**: Tool calls fail with permission denied
   - **Resolution**: Check ClusterRole has the required resource/verb. See Access section for RBAC scope details.

## References

- [kubectl-mcp-server GitHub](https://github.com/rohitg00/kubectl-mcp-server)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
