# brave-search-mcp - Brave Search MCP Server

## Overview

Web search for agents, exposed as an MCP server behind the LiteLLM MCP gateway. Callers are limited to the `litellm` namespace by CNP, and its only egress is `api.search.brave.com`.

## Prerequisites

- Brave Search API subscription; key in `app/brave-search-secrets.sops.yaml` (`BRAVE_API_KEY`), the only copy.

## Operations

- Declared as `mcp_servers.bravesearch` in the LiteLLM `config.yaml`, pointing at `http://brave-search-mcp.brave-search-mcp.svc:8000/mcp`. See [litellm README](../../litellm/README.md#mcp-servers).
- LiteLLM's own `brave-search` search tool uses a copy of the key: `litellm/app/brave-secret-store.yaml` pulls it into `litellm-brave` every 5m through ESO. `app/secret-reader-rbac.yaml` lets only the `litellm` reader ServiceAccount read `brave-search-secrets`, nothing else.
- To rotate, update `brave-search-secrets.sops.yaml` only. Reloader restarts this server when the Secret changes, and LiteLLM restarts once ESO has copied the new value (up to 5m).
- Some tools (e.g. video search) need a higher Brave plan tier; on a lower tier they return errors rather than being hidden.

## References

- [brave-search-mcp GitHub](https://github.com/brave/brave-search-mcp)
- [Brave Search API](https://api-dashboard.search.brave.com/)
