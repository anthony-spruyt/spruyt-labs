# MCP VictoriaLogs - Log Query MCP Server

## Overview

MCP server giving Claude read access to VictoriaLogs, including logs from pods that no longer exist.

## Operations

Reached only through the LiteLLM MCP gateway at `http://mcp-victorialogs.observability.svc:8080/mcp` (streamable HTTP). The server is registered and granted to keys/teams in the LiteLLM UI, not in Git; the only ingress this pod accepts is from LiteLLM.

`MCP_LOG_LEVEL=warn` is deliberate: at `info` the server logs every tool result, which Vector ships straight back into VictoriaLogs.

## Troubleshooting

1. **`victorialogs-*` tools missing in Claude Code**
   - **Fix**: Check the server is registered in the LiteLLM UI and granted to the key or team, and look for drops on the `allow-victorialogs-mcp-egress` CNP in the `litellm` namespace.
