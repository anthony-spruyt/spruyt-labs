# kubectl-mcp-server + MCP API Key Auth

**Date:** 2026-03-15
**Status:** Draft

## Summary

Deploy kubectl-mcp-server as an in-cluster MCP server accessible to Claude Code via Traefik, and add API key authentication to all MCP IngressRoutes using a Traefik plugin.

## Goals

1. Deploy kubectl-mcp-server in-cluster using bjw-s app-template, exposed via Traefik (LAN only)
2. Add API key authentication to MCP endpoints using a Traefik plugin
3. Retrofit existing VM MCP IngressRoute with API key auth
4. Configure Claude Code to connect to both MCP servers with API keys

## Non-Goals

- Moving mcp-victoriametrics out of the `observability` namespace
- Authentik integration for MCP auth
- In-cluster deployment via kMCP or kagent
- Public (non-LAN) access to MCP servers

## Architecture

```text
Claude Code (devcontainer)
  │
  ├── X-API-KEY: ${KUBECTL_MCP_API_KEY}
  │   → Traefik (websecure)
  │     → lan-ip-whitelist middleware
  │     → api-key-auth middleware (plugin)
  │     → kubectl-mcp-server.kubectl-mcp:8000
  │
  └── X-API-KEY: ${VM_MCP_API_KEY}
      → Traefik (websecure)
        → lan-ip-whitelist middleware
        → api-key-auth middleware (plugin)
        → mcp-victoriametrics.observability:8080
```

## Key Decisions

### kubectl-mcp-server deployment

- **Image:** `docker.io/rohitghumare64/kubectl-mcp-server` pinned by digest (no versioned tags published)
- **Transport:** `streamable-http` on port 8000 (current MCP standard, supported by Claude Code)
- **Namespace:** `kubectl-mcp` with privileged PSA (container requires root for kubectl binary)
- **RBAC:** Read-only ClusterRole (`get`, `list`, `watch`) including secrets — the `get_secrets` tool only returns metadata (name, namespace, type), not data values. Full `get` exists at RBAC level as a deliberate trade-off; the application masks data.
- **Network policies:** CiliumNetworkPolicy restricting ingress to Traefik and OpenClaw, egress to kube-apiserver only
- **Priority:** `low-priority` (not critical infrastructure)

### API key authentication

- **Plugin:** LinkPhoenix/traefik-api-key-auth v1.0.4
  - 310 lines of Go, zero external dependencies, stdlib only
  - Uses `crypto/subtle.ConstantTimeCompare` (timing-attack safe)
  - Does not log keys or config (unlike Septima, which logs both)
  - Supports `env:VAR_NAME` syntax to load keys from environment variables
  - Pin to v1.0.4; fork if upstream abandoned
- **Two separate keys:** Independent rotation and revocation per MCP endpoint
- **Key delivery:** SOPS-encrypted Secret mounted as env vars on Traefik pods, referenced by plugin via `env:` syntax
- **Claude Code config:** API keys passed via `X-API-KEY` header in `.mcp.json`, values sourced from env vars in devcontainer

### OpenClaw integration

- OpenClaw connects to MCP servers **pod-to-pod** (no Traefik, no API key) — secured by CNPs
- Add CNP egress rule for OpenClaw to kubectl-mcp-server on port 8000/TCP
- Add CNP ingress rule for kubectl-mcp-server from OpenClaw namespace
- **Manual step:** User updates `mcporter.json` in the `openclaw-workspace-config` SOPS secret to add the kubernetes MCP server endpoint

### VM MCP retrofit

- Add API key middleware to existing mcp-vm IngressRoute in observability ingress
- Add CiliumNetworkPolicy to mcp-victoriametrics (currently has none)

## Security Model

| Layer | Protection |
|-------|-----------|
| Network | LAN-only via `lan-ip-whitelist` Traefik middleware |
| Auth | API key via `X-API-KEY` header, validated by Traefik plugin (constant-time comparison) |
| RBAC | kubectl-mcp ServiceAccount: read-only ClusterRole |
| CNP | kubectl-mcp: ingress from Traefik + OpenClaw only, egress to kube-apiserver only |
| CNP | mcp-victoriametrics: ingress from Traefik + OpenClaw only, egress to VictoriaMetrics only |
| Secrets | `get_secrets` tool returns metadata only, not data values |
| Transport | TLS via cert-manager certificates |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Container runs as root | Required by kubectl binary; read-only ClusterRole limits blast radius |
| Docker image has no versioned tags | Pinned by digest; Renovate can track digest updates |
| Plugin author abandons repo | Pinned to v1.0.4; trivial to fork (310 lines, zero deps) |
| API key in env var on Traefik pod | Same trust boundary as other Traefik secrets; SOPS encrypted at rest |
| `helm_get_values` / `get_pod_logs` could expose sensitive data | Values don't contain secrets (SOPS/ExternalSecrets pattern); log exposure is same risk as current `kubectl logs` via Bash |

## Plugin Selection Rationale

Evaluated alternatives:

| Option | Verdict | Reason |
|--------|---------|--------|
| Septima/traefik-api-key-auth | Rejected | Logs API keys to stdout, uses `==` comparison (timing-attack vulnerable), no env var support |
| Aetherinox/traefik-api-token-middleware | Rejected | IP whitelisting redundant with existing middleware, no env var support |
| Traefik basicAuth (native) | Rejected | User preferred proper API key approach over shoehorning into basic auth |
| Authentik ForwardAuth | Rejected | Overkill for M2M; token expiry handling, redirect-on-failure behavior, complex setup |
| Traefik Hub API Key | N/A | Enterprise/paid only |
