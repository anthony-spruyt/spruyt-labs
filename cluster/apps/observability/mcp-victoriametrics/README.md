# MCP VictoriaMetrics - Metrics Query MCP Server

## Overview

MCP server giving Claude read access to VictoriaMetrics (queries, labels, alert rules).

## Operations

Reached only through the LiteLLM MCP gateway at `http://mcp-victoriametrics.observability.svc:8080/mcp` (streamable HTTP). The server is declared in the LiteLLM `config.yaml` (`mcp_servers.victoriametrics`) and granted to keys/teams in LiteLLM, and `app/network-policies.yaml` only admits LiteLLM. Agent pods get these tools through their LiteLLM key, not by calling the server directly.

## Troubleshooting

1. **`victoriametrics-*` tools missing in Claude Code**
   - **Fix**: Check the `mcp_servers.victoriametrics` entry in the LiteLLM `config.yaml` and that the server is granted to the key or team, and look for drops on the `allow-victoriametrics-mcp-egress` CNP in the `litellm` namespace.
