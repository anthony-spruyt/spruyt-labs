# n8n-mcp-server - n8n MCP Server

## Overview

Gives agents n8n node documentation, template search, workflow validation and workflow management against the in-cluster n8n, as an MCP server behind the LiteLLM MCP gateway. Only the `litellm` namespace can reach it, and its only egress is the n8n API.

## Prerequisites

- An n8n API key (created in n8n under Settings > n8n API) stored as `N8N_API_KEY` in `app/n8n-mcp-secrets.sops.yaml`. Workflow-management tools fail without it; documentation tools still work.
- `AUTH_TOKEN` in the same secret. n8n-mcp requires it in HTTP mode and validates it on every call (it cannot be disabled), so LiteLLM's registration for this server must send it as a bearer token.
- `N8N_MCP_ACCESS_TOKEN` in the same secret: the key from n8n under Settings > Instance-level MCP (MCP status Enabled). It is separate from `N8N_API_KEY` and unlocks the tools that go through n8n's own MCP server (running workflows without a webhook trigger, data table columns, native version history, `n8n_explore_node_resources`). Those tools only see workflows marked "Available in MCP".
  `n8n_manage_agents` stays unavailable: n8n Agents is an Enterprise feature.

## Operations

- Registered in LiteLLM through the UI at `http://n8n-mcp-server.n8n-mcp.svc:3000/mcp`; the registration and its auth header live in LiteLLM's database, not Git. See [litellm README](../../litellm/README.md#mcp-servers). Rotating `AUTH_TOKEN` means updating that registration too.
- The node database ships inside the image and is copied into an `emptyDir` by the `copy-db` init container. The server writes to it, and with a read-only root filesystem it fails with `attempt to write a readonly database` (#1119).
- n8n must allow the traffic too: `allow-n8n-mcp-ingress` in `n8n-system/n8n/app/network-policies.yaml`.

## Troubleshooting

1. **All tool calls return 401 from LiteLLM's side**

   - **Cause**: The token in LiteLLM's MCP registration does not match `AUTH_TOKEN`.
   - **Fix**: Re-align them.

2. **Documentation tools work, workflow tools fail**

   - **Cause**: `N8N_API_KEY` is invalid or revoked, or n8n is unreachable.
   - **Fix**: Create a new API key in n8n and update the secret; check `allow-n8n-mcp-ingress` exists in `n8n-system`.

## References

- [n8n-mcp GitHub](https://github.com/czlonkowski/n8n-mcp)
- [n8n API docs](https://docs.n8n.io/api/)
