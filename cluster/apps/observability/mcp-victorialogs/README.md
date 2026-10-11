# MCP VictoriaLogs - Log Query MCP Server

## Overview

MCP server giving Claude read access to VictoriaLogs, including logs from pods that no longer exist.

## Operations

Reached only through the LiteLLM MCP gateway at `http://mcp-victorialogs.observability.svc:8080/mcp` (streamable HTTP). The server is declared in the LiteLLM `config.yaml` (`mcp_servers.victorialogs`) and granted to keys/teams in LiteLLM; the only ingress this pod accepts is from LiteLLM.

`MCP_LOG_LEVEL=warn` is deliberate: at `info` the server logs every tool result, which Vector ships straight back into VictoriaLogs.

## Troubleshooting

1. **`victorialogs-*` tools missing in Claude Code**
   - **Fix**: Check the `mcp_servers.victorialogs` entry in the LiteLLM `config.yaml` and that the server is granted to the key or team, and look for drops on the `allow-victorialogs-mcp-egress` CNP in the `litellm` namespace.
