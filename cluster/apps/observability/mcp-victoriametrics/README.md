# MCP VictoriaMetrics - MCP Server for VictoriaMetrics

## Overview

MCP (Model Context Protocol) server that provides AI assistants with access to VictoriaMetrics metrics data. Enables Claude Code to query metrics, explore labels, analyze alerting rules, and debug queries without manual port-forwarding.

Deployed as a `low-priority` workload using bjw-s app-template.

## Prerequisites

- victoria-metrics-k8s-stack (metrics backend)

## Access

Reached only through the LiteLLM MCP gateway (`http://mcp-victoriametrics.observability.svc:8080/mcp`, streamable HTTP). The server is registered in the LiteLLM UI, not in Git, and is granted per key/team there.

| Consumer          | Path                                             |
| ----------------- | ------------------------------------------------ |
| Claude Code       | `litellm` MCP server → `victoriametrics-*` tools |
| Claude agent pods | Same, if their LiteLLM key has the server        |

## Troubleshooting

1. **MCP server cannot reach VMSingle**

   - **Symptom**: Connection refused or timeout in logs
   - **Resolution**: Verify VMSingle is running: `kubectl get pods -n observability -l app.kubernetes.io/name=vmsingle`

2. **Tools missing in Claude Code**

   - **Symptom**: No `victoriametrics-*` tools under the `litellm` MCP server
   - **Resolution**: Check the server is registered in the LiteLLM UI and granted to your key or team. Check for drops on the `allow-victoriametrics-mcp-egress` CNP in the `litellm` namespace.

## References

- [VictoriaMetrics MCP Server](https://github.com/VictoriaMetrics/mcp-victoriametrics)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
