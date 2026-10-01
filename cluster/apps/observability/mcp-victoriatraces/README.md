# MCP VictoriaTraces - Trace Query MCP Server

## Overview

MCP server giving Claude read access to VictoriaTraces spans.

## Operations

Reached only through the LiteLLM MCP gateway at `http://mcp-victoriatraces.observability.svc:8080/mcp` (streamable HTTP). The server is registered and granted to keys/teams in the LiteLLM UI, not in Git; the only ingress this pod accepts is from LiteLLM.

The image is published under `ghcr.io/victoriametrics-community/`, not `ghcr.io/victoriametrics/` like the logs and metrics MCPs.

## Troubleshooting

1. **`victoriatraces-*` tools missing in Claude Code**
   - **Fix**: Check the server is registered in the LiteLLM UI and granted to the key or team, and look for drops on the `allow-victoriatraces-mcp-egress` CNP in the `litellm` namespace or `allow-mcp-victoriatraces-ingress` on `vt-single`.
