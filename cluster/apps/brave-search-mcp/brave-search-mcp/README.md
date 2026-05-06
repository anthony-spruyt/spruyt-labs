# brave-search-mcp - Brave Search MCP Server

## Overview

MCP (Model Context Protocol) server providing AI assistants with web search capabilities via the Brave Search API. Runs in HTTP transport mode as a low-priority workload.

## Prerequisites

- Brave Search API key (stored in SOPS secret)

## Access

- **In-cluster only**: `http://brave-search-mcp.brave-search-mcp.svc:8000/mcp`
- **Network policies**: Ingress from claude-agents-read, claude-agents-write, and coder-workspaces namespaces; egress to api.search.brave.com only

## Troubleshooting

### Common Issues

1. **Pod fails to start**

   - **Symptom**: CrashLoopBackOff
   - **Resolution**: Check logs; likely missing or invalid BRAVE_API_KEY in brave-search-secrets.

1. **Search requests fail with 401/403**

   - **Symptom**: MCP tool calls return authentication errors
   - **Resolution**: Verify BRAVE_API_KEY is valid and the Brave Search plan is active.

1. **Search tool not available on plan**

   - **Symptom**: Specific tools (e.g., video search) return errors
   - **Resolution**: Check Brave Search plan tier; some tools require higher-tier plans.

## References

- [brave-search-mcp GitHub](https://github.com/brave/brave-search-mcp)
- [Brave Search API](https://api-dashboard.search.brave.com/)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
