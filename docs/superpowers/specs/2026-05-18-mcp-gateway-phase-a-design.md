# MCP Gateway Phase A — Design Spec

**Date:** 2026-05-18 **Issue:** #1142 **Status:** Draft **Requirements:** `docs/superpowers/plans/2026-05-16-mcp-gateway-requirements.md`

## Overview

Route all remote MCP servers (except agent-platform) through LiteLLM per-server endpoints (`/<server>/mcp`). Eliminates per-server ingresses, certificates, API key middlewares, and most per-consumer CNPs. Consolidates MCP credentials into LiteLLM config.

**Maturity note:** LiteLLM's MCP proxy lives under `litellm/proxy/_experimental/` — API surface may change on upgrades.

## Scope

**In scope:** Phase A only — per-server LiteLLM endpoints with access group partitioning.

**Out of scope:**

- LazyMCP / Phase B (PR #27842 not merged)
- Per-repo virtual keys / Phase C
- LiteLLM version upgrade (already on v1.85.0)
- Agent-platform MCP (stays direct — per-session auth, R7)
- Local stdio MCP servers like cclsp (C9)

## MCP Server Registration

Hybrid approach: config.yaml defines structure (url, transport, access_groups) for unauthenticated servers. Servers needing upstream credentials (context7, n8n-mcp) are registered via LiteLLM API — the `os.environ/` syntax is NOT resolved in the MCP config loader, only in `litellm_params` for model API keys.

**In config.yaml** (`cluster/apps/litellm/litellm/app/values.yaml`):

```yaml
mcp_servers:
  bravesearch:
    url: "http://brave-search-mcp.brave-search-mcp.svc:8000/mcp"
    transport: "http"
    access_groups: ["core"]

  agentmemory:
    url: "http://agentmemory.agentmemory.svc:3111/mcp"
    transport: "http"
    access_groups: ["core"]

  victoriametrics:
    url: "http://mcp-victoriametrics.observability.svc:8080/mcp"
    transport: "http"
    access_groups: ["observability"]
```

**Via LiteLLM UI** (manual, one-time — credentials cannot be handled by automation):

| Server   | URL                                          | Auth                                              | Access Groups |
| -------- | -------------------------------------------- | ------------------------------------------------- | ------------- |
| context7 | `https://mcp.context7.com/mcp`               | `static_headers: {"CONTEXT7_API_KEY": "<value>"}` | `core`        |
| n8n-mcp  | `http://n8n-mcp-server.n8n-mcp.svc:3000/mcp` | `auth_type: bearer_token`, `auth_value: <value>`  | `interactive` |

Persisted in PostgreSQL (CNPG), backed up to AWS. Survives restarts. Re-register only if DB is wiped or credentials rotate.

### Upstream Auth

| Server          | Auth to upstream                 | Mechanism                       |
| --------------- | -------------------------------- | ------------------------------- |
| bravesearch     | none                             | cluster-internal, CNP-protected |
| agentmemory     | none                             | cluster-internal, CNP-protected |
| context7        | `CONTEXT7_API_KEY` custom header | `static_headers` field          |
| victoriametrics | none                             | cluster-internal, CNP-protected |
| n8n-mcp         | Bearer token                     | `auth_type: bearer_token`       |

### Credential Delivery for UI-registered Servers

Context7 and n8n-mcp credentials are entered via the LiteLLM admin UI. No SOPS secret, env var, or setup script needed on the LiteLLM side. Credentials go directly into PostgreSQL.

## Access Control

### Access Groups

Defined per-server in `mcp_servers` config (see above):

- **`core`** — bravesearch, agentmemory, context7
- **`observability`** — victoriametrics
- **`interactive`** — n8n-mcp

### Team → Group Mapping

Configured via LiteLLM API after deploy. One-time setup.

| Team                            | Groups                                 | Servers visible                    |
| ------------------------------- | -------------------------------------- | ---------------------------------- |
| claude-agents-read              | `core`                                 | bravesearch, agentmemory, context7 |
| claude-agents-write             | `core`                                 | bravesearch, agentmemory, context7 |
| claude-agents-spruyt-labs-read  | `core`, `observability`                | + victoriametrics                  |
| claude-agents-spruyt-labs-write | `core`, `observability`                | + victoriametrics                  |
| claude-agents-spruyt-labs-sre   | `core`, `observability`                | + victoriametrics                  |
| coder-workspaces                | `core`, `observability`, `interactive` | + victoriametrics, n8n-mcp         |
| local-dev-containers            | `core`, `observability`, `interactive` | + victoriametrics, n8n-mcp         |
| agentmemory                     | (none)                                 | LLM API only, no MCP access        |

### Context Filtering

Agent `mcpServers` frontmatter (F6) controls which servers load per-agent. Access groups enforce at gateway level. Both layers work together:

- Access groups: what the team CAN access
- `mcpServers` frontmatter: what the agent DOES load

## Consumer MCP Config Updates

### Agent ConfigMaps (5 namespaces)

All agent configs point to LiteLLM per-server endpoints. Auth via existing `ANTHROPIC_AUTH_TOKEN` (LiteLLM virtual key already injected by Kyverno).

**Generic namespaces** (`claude-agents-read`, `claude-agents-write`):

```json
{
  "mcpServers": {
    "agentmemory": {
      "type": "http",
      "url": "http://litellm.litellm.svc.cluster.local:4000/agentmemory/mcp",
      "headers": { "Authorization": "Bearer $${ANTHROPIC_AUTH_TOKEN}" }
    },
    "agentplatform": {
      "type": "http",
      "url": "http://n8n-webhook.n8n-system.svc:8080/mcp/agent-platform",
      "headers": {
        "Authorization": "Bearer $${AGENT_PLATFORM_MCP_AUTH_TOKEN}",
        "X-MCP-Job-ID": "$${JOB_ID}",
        "X-MCP-Session-Token": "$${SESSION_TOKEN}"
      }
    },
    "bravesearch": {
      "type": "http",
      "url": "http://litellm.litellm.svc.cluster.local:4000/bravesearch/mcp",
      "headers": { "Authorization": "Bearer $${ANTHROPIC_AUTH_TOKEN}" }
    },
    "context7": {
      "type": "http",
      "url": "http://litellm.litellm.svc.cluster.local:4000/context7/mcp",
      "headers": { "Authorization": "Bearer $${ANTHROPIC_AUTH_TOKEN}" }
    }
  }
}
```

**Spruyt-labs namespaces** (`claude-agents-spruyt-labs-read/write/sre`) — same as above plus:

```json
{
  "victoriametrics": {
    "type": "http",
    "url": "http://litellm.litellm.svc.cluster.local:4000/victoriametrics/mcp",
    "headers": { "Authorization": "Bearer $${ANTHROPIC_AUTH_TOKEN}" }
  }
}
```

Key changes:

- **agentmemory**: stdio (npx) → HTTP through LiteLLM (R8)
- **bravesearch, context7**: direct → through LiteLLM
- **victoriametrics**: direct → through LiteLLM (spruyt-labs only)
- **agentplatform**: unchanged (direct, R7)
- **No n8n-mcp** in any agent config

### Interactive Config (`.mcp.json`)

Coder workspaces and local dev point to LiteLLM Traefik ingress:

```json
{
  "mcpServers": {
    "agentmemory": {
      "type": "http",
      "url": "https://litellm.${EXTERNAL_DOMAIN}/agentmemory/mcp",
      "headers": { "Authorization": "Bearer ${ANTHROPIC_AUTH_TOKEN}" }
    },
    "bravesearch": {
      "type": "http",
      "url": "https://litellm.${EXTERNAL_DOMAIN}/bravesearch/mcp",
      "headers": { "Authorization": "Bearer ${ANTHROPIC_AUTH_TOKEN}" }
    },
    "cclsp": {
      "type": "stdio",
      "command": "cclsp",
      "env": {
        "CCLSP_CONFIG_PATH": "/workspaces/spruyt-labs/.claude/cclsp.json"
      }
    },
    "context7": {
      "type": "http",
      "url": "https://litellm.${EXTERNAL_DOMAIN}/context7/mcp",
      "headers": { "Authorization": "Bearer ${ANTHROPIC_AUTH_TOKEN}" }
    },
    "n8n": {
      "type": "http",
      "url": "https://litellm.${EXTERNAL_DOMAIN}/n8n-mcp/mcp",
      "headers": { "Authorization": "Bearer ${ANTHROPIC_AUTH_TOKEN}" }
    },
    "victoriametrics": {
      "type": "http",
      "url": "https://litellm.${EXTERNAL_DOMAIN}/victoriametrics/mcp",
      "headers": { "Authorization": "Bearer ${ANTHROPIC_AUTH_TOKEN}" }
    }
  }
}
```

Key changes:

- All remote servers route through single LiteLLM ingress
- One auth key (`ANTHROPIC_AUTH_TOKEN`) replaces 3 separate MCP API keys
- `agentmemory` named entry overrides built-in stdio plugin (C10)
- `context7` built-in plugin will be uninstalled; LiteLLM gateway replaces it
- `cclsp` stays stdio unchanged (C9)

## Interactive Access

Interactive users (Coder workspaces, local dev) reach MCP endpoints via the existing WAN IngressRoute at `litellm.${EXTERNAL_DOMAIN}`. Split DNS resolves this to the internal IP from within the cluster. No new ingress needed.

## Network Policies

### Add: LiteLLM Egress to MCP Backends

In `cluster/apps/litellm/litellm/app/network-policies.yaml`:

| Policy                           | To namespace     | To pod              | Port |
| -------------------------------- | ---------------- | ------------------- | ---- |
| allow-brave-search-mcp-egress    | brave-search-mcp | brave-search-mcp    | 8000 |
| allow-agentmemory-mcp-egress     | agentmemory      | agentmemory         | 3111 |
| allow-victoriametrics-mcp-egress | observability    | mcp-victoriametrics | 8080 |
| allow-n8n-mcp-egress             | n8n-mcp          | n8n-mcp-server      | 3000 |

Context7 egress: already covered by existing world HTTPS (443) egress policy.

### Add: MCP Server Ingress from LiteLLM

Each MCP server namespace needs a CiliumNetworkPolicy allowing ingress from litellm:

| File                                                                       | Namespace        | From    | Port |
| -------------------------------------------------------------------------- | ---------------- | ------- | ---- |
| `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml` | brave-search-mcp | litellm | 8000 |
| `cluster/apps/agentmemory/agentmemory/app/network-policies.yaml`           | agentmemory      | litellm | 3111 |
| `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | observability    | litellm | 8080 |
| `cluster/apps/n8n-mcp/n8n-mcp-server/app/network-policies.yaml`            | n8n-mcp          | litellm | 3000 |

### Remove After Validation

From `cluster/apps/claude-agents-shared/base/network-policies.yaml`:

- `allow-brave-search-mcp-egress`
- `allow-agentmemory-egress`

From per-namespace policies (`claude-agents-spruyt-labs-*/network-policies.yaml`):

- `allow-victoriametrics-mcp-egress`

**Keep:** `allow-litellm-egress`, `allow-agent-platform-mcp-egress`

## Credential Consolidation

### New: LiteLLM MCP Credentials

No new SOPS secret needed. Context7 and n8n-mcp credentials registered via LiteLLM admin UI, persisted in PostgreSQL (CNPG, backed up to AWS).

### Remove: Agent-side Credentials

1. **Kyverno `inject-shared-config` rule** — remove `CONTEXT7_API_KEY` env injection, remove `AGENTMEMORY_URL`, remove `AGENTMEMORY_SECRET`
1. **`mcp-credentials.sops.yaml`** (agents-shared) — remove `context7-api-key` key. If `agent-platform-mcp-auth-token` is the only remaining key, keep the file for it.
1. **Kyverno `inject-managed-mcp` rule** — keep (still mounts ConfigMap + injects `AGENT_PLATFORM_MCP_AUTH_TOKEN`)

### Post-Validation Cleanup

Separate commit after gateway validated working:

1. **Traefik MCP ingresses** — remove:

   - `cluster/apps/traefik/traefik/ingress/brave-search-mcp/` (IngressRoute, Certificate, Middleware)
   - `cluster/apps/traefik/traefik/ingress/n8n-mcp/` (IngressRoute, Certificate, Middleware)
   - mcp-victoriametrics entries from `cluster/apps/traefik/traefik/ingress/observability/`
   - `agentmemory-mcp.lan` IngressRoute + Certificate from `cluster/apps/traefik/traefik/ingress/agentmemory/`

1. **Traefik MCP API keys** — remove:

   - `cluster/apps/traefik/traefik/app/mcp-api-keys-secrets.sops.yaml`
   - `cluster/apps/traefik/traefik/app/mcp-api-keys-reader-rbac.yaml`

1. **Coder ExternalSecrets** — remove:

   - `cluster/apps/coder-workspaces/coder-workspaces/app/mcp-api-keys-externalsecret.yaml`
   - `cluster/apps/coder-workspaces/coder-workspaces/app/mcp-api-keys-admin-externalsecret.yaml`
   - `cluster/apps/coder-workspaces/coder-workspaces/app/n8n-mcp-externalsecret.yaml`
   - `cluster/apps/coder-workspaces/coder-workspaces/app/mcp-api-keys-secret-store.yaml`
   - `cluster/apps/coder-workspaces/coder-workspaces/app/n8n-mcp-secret-store.yaml`

1. **Coder template env_from** — remove MCP API key secret refs from `spruyt-labs/main.tf` and `devcontainer/main.tf`

1. **Agent direct CNPs** — remove (listed in Network Policies section above)

1. **Coder workspace direct MCP CNPs** — remove direct MCP server egress from `cluster/apps/coder-workspaces/coder-workspaces/app/network-policies.yaml` (e.g., `allow-workspace-agentmemory-egress`)

1. **n8n-mcp cross-namespace RBAC** — remove `cluster/apps/n8n-mcp/n8n-mcp-server/app/mcp-api-keys-reader-rbac.yaml`

## Resource Adjustments

In `cluster/apps/litellm/litellm/app/values.yaml`:

- Memory request: 1280Mi → 1536Mi
- Memory limit: 2560Mi → 3072Mi

In `cluster/apps/litellm/litellm/app/vpa.yaml`:

- litellm VPA maxAllowed memory: 2560Mi → 3072Mi

## Ordering & Dependencies

### Phase 1: Infrastructure (must deploy before consumer changes)

1. LiteLLM `mcp_servers` config (3 unauthenticated servers) + resource bump + VPA
1. LiteLLM egress CNPs
1. MCP server ingress-from-litellm CNPs
1. Register context7 + n8n-mcp via LiteLLM UI (manual — user enters credentials)
1. Access group + team mapping via LiteLLM UI

### Phase 2: Consumer Migration (after infra validated)

6. Agent ConfigMaps (all 5 namespaces)
1. Kyverno policy updates (remove CONTEXT7_API_KEY, AGENTMEMORY_URL, AGENTMEMORY_SECRET)
1. `.mcp.json` update

### Phase 3: Cleanup (after gateway validated end-to-end)

9. Remove agent direct MCP CNPs
1. Remove Traefik MCP ingresses + certs + middlewares + API keys
1. Remove Coder ExternalSecrets + SecretStores
1. Remove Coder template MCP API key env_from
1. Remove `context7-api-key` from agents-shared `mcp-credentials.sops.yaml`

## Risks & Mitigations

| Risk                                                 | Likelihood | Mitigation                                                                                                                                                                                                                                                      |
| ---------------------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| LiteLLM MCP proxy adds latency                       | Low        | Per-server endpoints minimize overhead. Monitor tool call times.                                                                                                                                                                                                |
| Access group mechanism is per-key not per-team       | Medium     | Validate during Phase 1 whether `POST /team/update` supports `access_groups`. If not, set per-key via `POST /key/update`.                                                                                                                                       |
| OOMKill under concurrent MCP proxying                | Low        | Memory bumped to 3072Mi. VPA will scale requests. Monitor after deploy.                                                                                                                                                                                         |
| agentmemory plugin override broken by gateway URL    | Low        | Named `agentmemory` entry in MCP config overrides plugin. Same pattern works today.                                                                                                                                                                             |
| Context7 plugin not suppressed for interactive users | Medium     | Named `context7` entry in `.mcp.json` overrides built-in plugin. Verify after deploy.                                                                                                                                                                           |
| Presidio/guardrails interfere with MCP proxy traffic | Medium     | LiteLLM has `default_on: true` guardrails (PII masking, prompt injection). May block legitimate MCP tool call content (IP addresses in VM queries, person names). Test during Phase 1. If interference detected, configure guardrail exemptions for MCP routes. |
| UI-registered servers lost if PostgreSQL is wiped    | Low        | CNPG has automated backups to AWS. Re-register via UI if needed.                                                                                                                                                                                                |

## Verification Checklist

- [ ] `GET /v1/mcp/registry.json` returns all 5 servers
- [ ] Per-server tool discovery: `GET /<server>/mcp` returns tools for each server
- [ ] Access group enforcement: generic agent key can't reach victoriametrics or n8n-mcp
- [ ] Context7 auth: tools load through gateway (static_headers working via API registration)
- [ ] n8n-mcp auth: tools load through gateway (bearer_token working via API registration)
- [ ] Guardrails: Presidio PII masking does not corrupt MCP tool call arguments (test VM queries with IPs)
- [ ] Agent pods: agentmemory tools work via HTTP (no stdio)
- [ ] Agent pods: all MCP tools functional through gateway
- [ ] Coder workspace: all MCP tools functional through gateway
- [ ] Local dev: all MCP tools functional through gateway
- [ ] Plugin suppression: agentmemory and context7 named entries override plugins
- [ ] No OOMKill on LiteLLM after MCP proxy load
- [ ] Agent-platform MCP still works (direct connection, not through gateway)
