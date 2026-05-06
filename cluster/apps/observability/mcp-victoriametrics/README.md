# MCP VictoriaMetrics - MCP Server for VictoriaMetrics

## Overview

MCP (Model Context Protocol) server that provides AI assistants with access to VictoriaMetrics metrics data. Enables Claude Code to query metrics, explore labels, analyze alerting rules, and debug queries without manual port-forwarding.

Deployed as a `low-priority` workload using bjw-s app-template.

## Prerequisites

- victoria-metrics-k8s-stack (metrics backend)

## Access

| Consumer                    | URL                                         | Transport                    |
| --------------------------- | ------------------------------------------- | ---------------------------- |
| Claude Code (dev container) | `https://mcp-vm.lan.${EXTERNAL_DOMAIN}/sse` | SSE over HTTPS (LAN-only)    |
| Streamable HTTP             | Same host, `/mcp` endpoint                  | HTTP (alternative transport) |

## Troubleshooting

1. **MCP server cannot reach VMSingle**

   - **Symptom**: Connection refused or timeout in logs
   - **Resolution**: Verify VMSingle is running: `kubectl get pods -n observability -l app.kubernetes.io/name=vmsingle`

1. **Claude Code cannot connect**

   - **Symptom**: MCP connection error in Claude Code
   - **Resolution**: Verify IngressRoute is active: `kubectl get ingressroute -n observability ingress-routes-lan-https-mcp-vm` and certificate is ready: `kubectl get certificate -n observability -l app.kubernetes.io/name=mcp-victoriametrics`

## References

- [VictoriaMetrics MCP Server](https://github.com/VictoriaMetrics/mcp-victoriametrics)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
