# brave-search-mcp - Brave Search MCP Server

## Overview

Web search for agents, exposed as an MCP server behind the LiteLLM MCP gateway. The server itself has no caller authentication; only the `litellm` namespace can reach it, and its only egress is `api.search.brave.com`.

## Prerequisites

- Brave Search API subscription; key in `app/brave-search-secrets.sops.yaml` (`BRAVE_API_KEY`). LiteLLM's own `brave-search` search tool reads a separate `BRAVE_API_KEY` from `litellm-secrets`; when rotating the Brave key, check both.

## Operations

- Registered in LiteLLM through the UI at `http://brave-search-mcp.brave-search-mcp.svc:8000/mcp`; the registration lives in LiteLLM's database, not Git. See [litellm README](../../litellm/README.md#mcp-servers).
- Some tools (e.g. video search) need a higher Brave plan tier; on a lower tier they return errors rather than being hidden.

## References

- [brave-search-mcp GitHub](https://github.com/brave/brave-search-mcp)
- [Brave Search API](https://api-dashboard.search.brave.com/)
