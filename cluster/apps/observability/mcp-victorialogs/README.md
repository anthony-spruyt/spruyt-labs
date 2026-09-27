# MCP VictoriaLogs - MCP Server for VictoriaLogs

## Overview

MCP (Model Context Protocol) server that gives AI assistants read access to VictoriaLogs. Lets Claude query pod logs, including logs from deleted pods, without exec-ing into or port-forwarding to the VictoriaLogs pod.

Deployed as a `low-priority` workload using bjw-s app-template. Tenant defaults to `0:0`, which is what `victoria-logs-single` uses.

## Prerequisites

- victoria-logs-single (logs backend)

## Access

Reached only through the LiteLLM MCP gateway (`http://mcp-victorialogs.observability.svc:8080/mcp`, streamable HTTP). The server is registered in the LiteLLM UI, not in Git, and is granted per key/team there.

| Consumer          | Path                                          |
| ----------------- | --------------------------------------------- |
| Claude Code       | `litellm` MCP server → `victorialogs-*` tools |
| Claude agent pods | Same, if their LiteLLM key has the server     |

## Troubleshooting

1. **MCP server cannot reach VictoriaLogs**

   - **Symptom**: Connection refused or timeout in logs
   - **Resolution**: Verify VictoriaLogs is running: `kubectl get pods -n observability -l app.kubernetes.io/name=victoria-logs-single`

2. **Tools missing in Claude Code**

   - **Symptom**: No `victorialogs-*` tools under the `litellm` MCP server
   - **Resolution**: Check the server is registered in the LiteLLM UI and granted to your key or team. Check for drops on the `allow-victorialogs-mcp-egress` CNP in the `litellm` namespace.

## References

- [VictoriaLogs MCP Server](https://github.com/VictoriaMetrics-Community/mcp-victorialogs)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
