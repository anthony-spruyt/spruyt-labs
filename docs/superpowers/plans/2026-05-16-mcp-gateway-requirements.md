# MCP Gateway Consolidation — Requirements

**Date:** 2026-05-16 **Status:** Draft

## Problem Statement

MCP servers are independently deployed, exposed, and configured. Each server requires its own ingress, certificate, API key middleware, Cilium CNPs per consumer namespace, and entries in per-namespace MCP ConfigMaps. Adding or removing an MCP server touches 6+ files across multiple directories. Agent images bake in stdio MCP tools (agentmemory npx).

## Consumer Types

| Consumer                | Where it runs                                            | How MCP config is provided        | Interactive? |
| ----------------------- | -------------------------------------------------------- | --------------------------------- | :----------: |
| Agent pods (read role)  | `claude-agents-read`, `claude-agents-spruyt-labs-read`   | ConfigMap + Kyverno injection     |      No      |
| Agent pods (write role) | `claude-agents-write`, `claude-agents-spruyt-labs-write` | ConfigMap + Kyverno injection     |      No      |
| Agent pods (SRE role)   | `claude-agents-spruyt-labs-sre`                          | ConfigMap + Kyverno injection     |      No      |
| Coder workspaces        | `coder-workspaces` namespace                             | Coder template + ExternalSecrets  |     Yes      |
| Local dev containers    | Developer machine                                        | `.mcp.json` / devcontainer config |     Yes      |

### Namespace → Repo mapping

| Namespace                         | Repo scope       | Notes                                         |
| --------------------------------- | ---------------- | --------------------------------------------- |
| `claude-agents-read`              | Many repos       | Generic read-only, shared across repos        |
| `claude-agents-write`             | Many repos       | Generic write, shared across repos            |
| `claude-agents-spruyt-labs-read`  | spruyt-labs only | Dedicated to this repo                        |
| `claude-agents-spruyt-labs-write` | spruyt-labs only | Dedicated to this repo                        |
| `claude-agents-spruyt-labs-sre`   | spruyt-labs only | Dedicated to this repo                        |
| `coder-workspaces`                | Many repos       | User switches between repos in same workspace |

## Current MCP Servers

| Server                       | Namespace                   | Transport                             | Used by                                                         |
| ---------------------------- | --------------------------- | ------------------------------------- | --------------------------------------------------------------- |
| brave-search-mcp             | `brave-search-mcp`          | HTTP :8000                            | All agents, Coder, local dev                                    |
| agentmemory                  | `agentmemory`               | HTTP :3111 (+ stdio client in agents) | All agents, Coder, local dev                                    |
| mcp-victoriametrics          | `observability`             | HTTP :8080                            | spruyt-labs agents (read/write/SRE), Coder, local dev           |
| n8n-mcp                      | `n8n-mcp`                   | HTTP :3000                            | spruyt-labs-read/write agents, Coder, local dev                 |
| context7                     | External (mcp.context7.com) | HTTPS                                 | All agents, Coder, local dev                                    |
|                              |                             |                                       | *Agents: explicit HTTP config + API key via Kyverno env var*    |
|                              |                             |                                       | *Interactive: Claude Code built-in plugin (no explicit config)* |
| agent-platform (n8n-webhook) | `n8n-system`                | HTTP :8080                            | All agents only (per-session auth)                              |

## Requirements

### R1: Centralized gateway

All MCP traffic (except agent-platform) routes through a single gateway. Eliminates per-server ingresses, certificates, API key middlewares, and most per-consumer CNPs.

### R2: Role-based tool access

Different roles see different tools. Read agents don't need victoriametrics. SRE agents need everything. The gateway must restrict tool visibility by role, not just block calls.

### R3: Repo-aware tool access

Different repos may need different MCP servers. Agents working on repo A might need tools that repo B doesn't. Generic namespaces (`claude-agents-read/write`) serve many repos — tool access must vary by repo within the same namespace.

### R4: Context efficiency

Agents and interactive users should only load tool schemas they actually need. Loading 50 tools when an agent only uses 5 wastes context tokens and degrades performance. Tool schemas not relevant to the current role/repo should not appear in the tool list.

### R5: Interactive toggle control

Interactive users (Coder workspaces, local dev) must be able to enable/disable individual MCP tool sets without affecting others. Example: disable n8n-mcp when not working on n8n, keep everything else.

### R6: Low maintenance onboarding

Adding a new MCP server should require minimal changes:

- Register in gateway config
- Assign to appropriate access groups
- Ideally zero changes to consumer configs (agent ConfigMaps, Coder templates, .mcp.json)

### R7: Agent-platform stays direct

Agent-platform MCP uses per-session auth (job ID + session token). This is per-job security, not per-team. Must remain a direct connection, not proxied through gateway.

### R8: Remove stdio from agent images

Agentmemory currently uses `npx @agentmemory/mcp` stdio transport baked into agent pods. Replace with HTTP through gateway. Eliminates npm/Node.js dependency in agent images.

### R9: Preserve tool name compatibility

18 hardcoded tool name refs exist across agents/skills. Migration must either preserve existing names or update them in a single coordinated change. After migration, tool names must be stable.

### R10: Resource headroom

Gateway must handle MCP proxying without OOMKill. Current LiteLLM at 685Mi/2560Mi. Proxying 5 servers with concurrent agents adds load. VPA must be correctly configured.

### R11: Credential consolidation

MCP server credentials (API keys, auth tokens) should live only in LiteLLM's config, not scattered across SOPS secrets, Kyverno injection policies, and agent pod env vars. Context7 API key is the primary example: currently in `mcp-credentials` SOPS secret → Kyverno injects `CONTEXT7_API_KEY` env var → every agent pod. Post-gateway, only LiteLLM needs this key.

## Constraints

### C1: LiteLLM tool name prefixing

LiteLLM's single `/mcp` endpoint prefixes tool names with server alias (`victoriametrics-query` instead of `query`). Claude Code sees these as `mcp__litellm__victoriametrics-query`. Per-server endpoints (`/mcp/<server>/mcp`) preserve original names.

### C2: Claude Code tool loading

Claude Code loads ALL tool schemas from every connected MCP server into context. No lazy loading. More servers = more context consumed, regardless of whether tools are used.

### C3: Claude Code MCP toggle granularity

Claude Code can enable/disable MCP servers individually. If all tools come through one server, it's all-or-nothing. Per-server entries give granular toggle control.

### C4: LiteLLM access control model

LiteLLM resolves access from the API key → team → access groups → MCP servers. No native support for request-metadata-based (e.g., repo URL) access control. Repo-awareness must be implemented at the key selection layer.

### C5: Generic namespaces serve many repos

`claude-agents-read` and `claude-agents-write` handle multiple repos. A single virtual key per namespace means all repos in that namespace get the same MCP tool set.

### C6: Network policy requirements

Bidirectional CNPs needed: LiteLLM egress to each MCP server + MCP server ingress from LiteLLM namespace. Must be in place before any traffic flows.

### C7: Agent-platform per-session auth

Agent-platform MCP has dynamic per-request headers (job ID, session token) that prevent proxying through a shared gateway. Separate connection required.

### C8: Context7 custom auth header

Context7 uses a non-standard `CONTEXT7_API_KEY` header. LiteLLM's `auth_type: "api_key"` sends `X-API-Key`. Compatibility needs verification. Moving Context7 behind LiteLLM means only LiteLLM needs the API key — eliminates `CONTEXT7_API_KEY` env var from all agent pods (currently injected via Kyverno from `mcp-credentials` SOPS secret).

### C9: Local/stdio MCP servers cannot be gateway-proxied

Some MCP servers run as local processes via stdio transport (e.g., `cclsp` for language server protocol). These need local filesystem access and sub-millisecond latency. They cannot route through a remote gateway.

| Category      | Transport | Examples                                                      | Gateway-able? |
| ------------- | --------- | ------------------------------------------------------------- | :-----------: |
| Remote/shared | HTTP      | brave-search, agentmemory, victoriametrics, n8n-mcp, context7 |      Yes      |
| Local/process | stdio     | cclsp, future local dev tools                                 |      No       |

Consumer MCP configs will always contain local stdio entries alongside gateway entries. "Zero consumer config changes" only applies to remote MCP servers. Adding a new local MCP server always requires per-consumer config updates.

### C10: Plugin-installed MCP servers need name override

The agentmemory Claude Code plugin installs a stdio MCP server named `"agentmemory"`. We override it by declaring an MCP server with the same name pointing to the remote shared instance. This name collision is intentional — config entry takes precedence over plugin.

Implications for gateway design:

- **Per-server endpoints**: Override still works — entry named `"agentmemory"` points to `litellm:4000/mcp/agentmemory/mcp`. Plugin suppressed.
- **Single endpoint (LazyMCP)**: Gateway entry is `"litellm"`, not `"agentmemory"`. Plugin's stdio server remains active. Results in **duplicate tools** (plugin local + gateway remote).
- **Mitigation**: Any MCP server that's also a Claude Code plugin requires a named per-server entry to suppress the plugin's stdio fallback, even when other servers use a single endpoint.

### C11: Context7 plugin vs explicit config divergence

Interactive users (Coder, local dev) get Context7 from Claude Code's built-in plugin (`plugin:context7:context7`). Agent pods override this with explicit HTTP MCP config pointing to `mcp.context7.com` with API key header. Post-gateway, both should point to LiteLLM's `/mcp/context7/mcp`. The built-in plugin must be overridden in interactive configs (same pattern as agentmemory plugin override in
C10). The `CONTEXT7_API_KEY` env var and its Kyverno injection + SOPS secret entry become removable once LiteLLM handles auth.

## Research Findings

### F1: LiteLLM tool list filtering — UNVERIFIED

Whether `/mcp` tool list is filtered per-key or returns all tools with call-time blocking is not documented. Needs runtime test. Access groups and per-key `mcp_servers` are enforced (PR #22743, #27692), suggesting list filtering is likely but unconfirmed.

### F2: Per-key MCP server access — SUPPORTED

`/key/generate` accepts `object_permission.mcp_servers` and `object_permission.mcp_access_groups`. Keys can have different MCP access within the same team. Validation enforced: keys can only access servers their team permits (intersection).

### F3: Access groups — WORKING (bugs recently fixed)

Bundle MCP server IDs, assign to teams/keys. No composition/nesting — each group manually enumerates servers. Manageable at current scale (5 servers). Managed via API or LiteLLM dashboard.

### F4: Request-metadata routing — NOT SUPPORTED

No native mechanism to resolve repo/context from request headers. LiteLLM access model is strictly: API key → team → access groups → MCP servers. Custom middleware could bridge this gap.

### F5: LazyMCP — IN DEVELOPMENT (PR #27842, expected v1.85+)

Game-changing feature. Single `/lazymcp` endpoint exposes 3 meta-tools (`mcp_status`, `mcp_describe`, `mcp_call`). Tools discovered on-demand, not pre-loaded. ~75% context reduction. Preserves all access controls. Per-toolset and per-server scoping via `/toolset/{name}/lazymcp` and `/lazymcp/{server}`.

### F6: Claude Code agent `mcpServers` frontmatter — ALREADY EXISTS

Agents can declare `mcpServers: ["victoriametrics"]` to restrict which MCP servers are loaded into context. Works at server level (not tool level). Already used by `cnp-drop-investigator` in this repo.

### F7: MCP Toolsets — API-ONLY

Curated bundles of {server, tool} pairs. Not configurable via `config.yaml` (feature request #27287). Managed via API/dashboard. Not composable.

### F8: Per-repo virtual keys — POSSIBLE VIA ORCHESTRATION

Create keys with repo-specific `mcp_servers` via `/key/generate`. n8n (or Kyverno) injects repo-specific key. Requires key management lifecycle. Not dynamic — new repo = create new key.

## Tensions

| Requirement             | Conflicts with          | Trade-off                                                                                                                       |
| ----------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| R6 (low maintenance)    | R5 (toggle control)     | Single endpoint = zero consumer changes but no toggle. Per-server = toggle but per-consumer config.                             |
| R6 (low maintenance)    | R4 (context efficiency) | Single endpoint loads all allowed tools. Per-server + agent `mcpServers` frontmatter = selective. LazyMCP (future) solves both. |
| R3 (repo-aware)         | C5 (shared namespaces)  | Per-repo virtual keys via `/key/generate` + orchestration. Not native, requires key management.                                 |
| R9 (tool name compat)   | C1 (prefixing)          | Single endpoint changes names (one-time migration of 18 refs). Per-server preserves them.                                       |
| R4 (context efficiency) | R2 (role-based access)  | Agent `mcpServers` frontmatter already filters at server level per-agent. Works with per-server endpoints today.                |

## Emerging Strategy

### Phase A — Now (v1.84.0): Per-server LiteLLM endpoints

Per-server endpoints (`/mcp/<server>/mcp`) through LiteLLM. Each consumer MCP config lists individual servers pointing to LiteLLM. Access groups restrict which servers each team can reach.

| Satisfies                      | How                                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------------- |
| R1 (gateway)                   | All traffic through LiteLLM                                                                          |
| R2 (role-based)                | Access groups per team                                                                               |
| R4 (context)                   | Agent `mcpServers` frontmatter filters per-agent                                                     |
| R5 (toggle)                    | Per-server entries individually toggle-able                                                          |
| R7 (agent-platform direct)     | Stays separate                                                                                       |
| R8 (remove stdio)              | Agentmemory via HTTP through LiteLLM                                                                 |
| R9 (tool names)                | Preserved — per-server endpoints keep original names                                                 |
| R10 (resources)                | VPA fix + memory bump                                                                                |
| R11 (credential consolidation) | Context7 API key moves to LiteLLM config; remove from SOPS secret, Kyverno injection, agent env vars |

| Partially satisfies  | Gap                                                                                                                           |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| R3 (repo-aware)      | Access groups per team, not per repo. Per-repo keys possible via orchestration if needed.                                     |
| R6 (low maintenance) | Adding server = LiteLLM config + update consumer MCP configs. Better than today (no CNPs/ingresses/certs) but not zero-touch. |

### Phase B — When available (v1.85+): LazyMCP migration

Switch from per-server endpoints to single `/lazymcp` endpoint. Tools discovered on-demand.

| Now satisfies        | How                                                                                                     |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| R4 (context)         | On-demand discovery, ~75% context reduction                                                             |
| R6 (low maintenance) | Single endpoint — adding server = LiteLLM config only, zero consumer changes                            |
| R9 (tool names)      | LazyMCP uses server-prefixed names but tools loaded individually — context cost is per-use not per-list |

| Trade-off       | Acceptance                                                                         |
| --------------- | ---------------------------------------------------------------------------------- |
| R5 (toggle)     | Single endpoint = no toggle. Acceptable since context isn't wasted (lazy loading). |
| R9 (tool names) | One-time migration of 18 refs when switching to LazyMCP.                           |

### Phase C — If needed: Per-repo keys

Only if repo-level isolation within shared namespaces becomes a real requirement.

- Create per-repo keys via `/key/generate` with specific `mcp_servers`
- n8n selects key based on repo at dispatch time
- Kyverno or init container injects correct key into pod

## Open Design Questions

1. ~~**Single vs per-server vs hybrid?**~~ — **ANSWERED.** Per-server now (Phase A), LazyMCP later (Phase B).

1. ~~**Repo-aware access?**~~ — **ANSWERED.** Team-level access groups for now. Per-repo keys via `/key/generate` + orchestration if needed later (Phase C). No native request-metadata routing.

1. **Where does repo → MCP tool set mapping live?** — LiteLLM access groups (team-level). If per-repo keys needed, mapping in n8n or a ConfigMap.

1. **Does LiteLLM filter tool list per key?** — UNVERIFIED. Needs runtime test in Phase 1. Affects whether single `/mcp` endpoint is context-efficient. Less critical now that strategy uses per-server endpoints for Phase A.

1. ~~**Maintenance budget?**~~ — **ANSWERED.** Phase A: LiteLLM config + consumer configs (better than today). Phase B: LiteLLM config only (zero consumer changes).
