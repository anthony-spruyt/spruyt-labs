# MCP VictoriaMetrics - MCP Server for VictoriaMetrics

## Overview

MCP (Model Context Protocol) server that provides AI assistants with access to VictoriaMetrics metrics data. Enables Claude Code and OpenClaw to query metrics, explore labels, analyze alerting rules, and debug queries without manual port-forwarding.

Deployed as a `low-priority` workload using bjw-s app-template.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- victoria-metrics-k8s-stack (metrics backend)

## Access

| Consumer | URL | Transport |
|----------|-----|-----------|
| Claude Code (dev container) | `https://mcp-vm.lan.${EXTERNAL_DOMAIN}/sse` | SSE over HTTPS (LAN-only) |
| OpenClaw (in-cluster) | `http://mcp-victoriametrics-app.observability.svc.cluster.local:8080/sse` | SSE over HTTP (cluster DNS) |
| Streamable HTTP | Same hosts, `/mcp` endpoint | HTTP (alternative transport) |

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n observability -l app.kubernetes.io/name=mcp-victoriametrics
flux get helmrelease -n observability mcp-victoriametrics

# Force reconcile (GitOps approach)
flux reconcile kustomization mcp-victoriametrics --with-source

# View logs
kubectl logs -n observability -l app.kubernetes.io/name=mcp-victoriametrics

# Test health
kubectl exec -it deploy/mcp-victoriametrics -n observability -- wget -qO- http://localhost:8080/health/readiness
```

## Troubleshooting

### Common Issues

1. **MCP server cannot reach VMSingle**
   - **Symptom**: Connection refused or timeout in logs
   - **Resolution**: Verify VMSingle is running: `kubectl get pods -n observability -l app.kubernetes.io/name=vmsingle`

2. **Claude Code cannot connect**
   - **Symptom**: MCP connection error in Claude Code
   - **Resolution**: Verify IngressRoute is active: `kubectl get ingressroute -n observability ingress-routes-lan-https-mcp-vm` and certificate is ready: `kubectl get certificate -n observability -l app.kubernetes.io/name=mcp-victoriametrics`

3. **OpenClaw cannot connect**
   - **Symptom**: MCP connection error in OpenClaw logs
   - **Resolution**: Verify CNP allows egress: `kubectl get cnp -n openclaw allow-mcp-vm-egress`

## References

- [VictoriaMetrics MCP Server](https://github.com/VictoriaMetrics/mcp-victoriametrics)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
