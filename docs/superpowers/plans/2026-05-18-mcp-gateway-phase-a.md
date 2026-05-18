# MCP Gateway Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route all remote MCP servers through LiteLLM per-server endpoints, eliminating per-server ingresses and consolidating credentials.

**Architecture:** LiteLLM gains `mcp_servers` config for 3 unauthenticated backends (bravesearch, agentmemory, victoriametrics). Two authenticated servers (context7, n8n-mcp) are registered via LiteLLM UI. Consumer MCP configs updated to route through LiteLLM. Network policies enable bidirectional traffic.

**Tech Stack:** LiteLLM v1.85.0, Cilium CNPs, Traefik IngressRoutes, Kyverno ClusterPolicies, Flux GitOps

**Spec:** `docs/superpowers/specs/2026-05-18-mcp-gateway-phase-a-design.md` **Issue:** #1142

______________________________________________________________________

## File Map

### Phase 1: Infrastructure

| Action | File                                                                       | Purpose                               |
| ------ | -------------------------------------------------------------------------- | ------------------------------------- |
| Modify | `cluster/apps/litellm/litellm/app/values.yaml`                             | Add `mcp_servers` config, bump memory |
| Modify | `cluster/apps/litellm/litellm/app/vpa.yaml`                                | Bump VPA maxAllowed                   |
| Modify | `cluster/apps/litellm/litellm/app/network-policies.yaml`                   | Add egress to 4 MCP backends          |
| Modify | `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml` | Add ingress from litellm              |
| Modify | `cluster/apps/agentmemory/agentmemory/app/network-policies.yaml`           | Add ingress from litellm              |
| Modify | `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | Add ingress from litellm              |
| Modify | `cluster/apps/n8n-mcp/n8n-mcp-server/app/network-policies.yaml`            | Add ingress from litellm              |

### Phase 2: Consumer Migration

| Action | File                                                                                    | Purpose                                                                 |
| ------ | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Modify | `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml`              | Point to LiteLLM gateway                                                |
| Modify | `cluster/apps/claude-agents-write/claude-agents/app/claude-mcp-config.yaml`             | Point to LiteLLM gateway                                                |
| Modify | `cluster/apps/claude-agents-spruyt-labs-read/claude-agents/app/claude-mcp-config.yaml`  | Point to LiteLLM gateway                                                |
| Modify | `cluster/apps/claude-agents-spruyt-labs-write/claude-agents/app/claude-mcp-config.yaml` | Point to LiteLLM gateway                                                |
| Modify | `cluster/apps/claude-agents-spruyt-labs-sre/claude-agents/app/claude-mcp-config.yaml`   | Point to LiteLLM gateway                                                |
| Modify | `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`                     | Remove CONTEXT7_API_KEY, AGENTMEMORY_URL, AGENTMEMORY_SECRET            |
| Modify | `.mcp.json`                                                                             | Point interactive users to LiteLLM via existing WAN ingress (split DNS) |

______________________________________________________________________

## Task 1: LiteLLM Config — Add mcp_servers and Bump Resources

**Files:**

- Modify: `cluster/apps/litellm/litellm/app/values.yaml:123-128` (resources)

- Modify: `cluster/apps/litellm/litellm/app/values.yaml:693-695` (after router_settings)

- Modify: `cluster/apps/litellm/litellm/app/vpa.yaml:22` (maxAllowed)

- [ ] **Step 1: Add `mcp_servers` block to config.yaml section**

In `cluster/apps/litellm/litellm/app/values.yaml`, after line 695 (`cooldown_time: 300`), add:

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

Indentation: 8 spaces (same level as `model_list`, `litellm_settings`, `router_settings`).

- [ ] **Step 2: Bump LiteLLM memory resources**

In the same file, change lines 123-128:

```yaml
        resources:
          limits:
            memory: 3072Mi
          requests:
            cpu: 100m
            memory: 1536Mi
```

- [ ] **Step 3: Bump VPA maxAllowed**

In `cluster/apps/litellm/litellm/app/vpa.yaml`, change line 22:

```yaml
          memory: 3072Mi
```

- [ ] **Step 4: Validate syntax**

Run: `task dev-env:yaml-lint -- cluster/apps/litellm/litellm/app/values.yaml cluster/apps/litellm/litellm/app/vpa.yaml`

Expected: No errors.

______________________________________________________________________

## Task 2: LiteLLM Egress CNPs to MCP Backends

**Files:**

- Modify: `cluster/apps/litellm/litellm/app/network-policies.yaml` (append after line 515)

- [ ] **Step 1: Add 4 egress CNPs**

Append to `cluster/apps/litellm/litellm/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress from LiteLLM to Brave Search MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-brave-search-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: litellm
      app.kubernetes.io/name: litellm
      app.kubernetes.io/controller: litellm
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: brave-search-mcp
            k8s:app.kubernetes.io/name: brave-search-mcp
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress from LiteLLM to Agentmemory MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-agentmemory-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: litellm
      app.kubernetes.io/name: litellm
      app.kubernetes.io/controller: litellm
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: agentmemory
            k8s:app.kubernetes.io/name: agentmemory
      toPorts:
        - ports:
            - port: "3111"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress from LiteLLM to VictoriaMetrics MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-victoriametrics-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: litellm
      app.kubernetes.io/name: litellm
      app.kubernetes.io/controller: litellm
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: mcp-victoriametrics
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress from LiteLLM to n8n MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-n8n-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: litellm
      app.kubernetes.io/name: litellm
      app.kubernetes.io/controller: litellm
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: n8n-mcp
            k8s:app.kubernetes.io/name: n8n-mcp-server
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
```

______________________________________________________________________

## Task 3: MCP Server Ingress CNPs from LiteLLM

**Files:**

- Modify: `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml`

- Modify: `cluster/apps/agentmemory/agentmemory/app/network-policies.yaml`

- Modify: `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`

- Modify: `cluster/apps/n8n-mcp/n8n-mcp-server/app/network-policies.yaml`

- [ ] **Step 1: Add ingress-from-litellm to brave-search-mcp**

Append to `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from LiteLLM MCP gateway
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-litellm-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: brave-search-mcp
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: litellm
            k8s:app.kubernetes.io/name: litellm
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

- [ ] **Step 2: Add ingress-from-litellm to agentmemory**

Append to `cluster/apps/agentmemory/agentmemory/app/network-policies.yaml` (before the Authentik Outpost section):

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from LiteLLM MCP gateway
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-litellm-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: agentmemory
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: litellm
            k8s:app.kubernetes.io/name: litellm
      toPorts:
        - ports:
            - port: "3111"
              protocol: TCP
```

- [ ] **Step 3: Add ingress-from-litellm to mcp-victoriametrics**

Append to `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from LiteLLM MCP gateway
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-litellm-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-victoriametrics
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: litellm
            k8s:app.kubernetes.io/name: litellm
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

- [ ] **Step 4: Add ingress-from-litellm to n8n-mcp**

Append to `cluster/apps/n8n-mcp/n8n-mcp-server/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from LiteLLM MCP gateway
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-litellm-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: n8n-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: litellm
            k8s:app.kubernetes.io/name: litellm
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
```

______________________________________________________________________

## Task 4: Commit and Push Phase 1 Infrastructure

- [ ] **Step 1: Run qa-validator**

Validate all modified files before committing.

- [ ] **Step 2: Commit Phase 1**

```bash
git add \
  cluster/apps/litellm/litellm/app/values.yaml \
  cluster/apps/litellm/litellm/app/vpa.yaml \
  cluster/apps/litellm/litellm/app/network-policies.yaml \
  cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml \
  cluster/apps/agentmemory/agentmemory/app/network-policies.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml \
  cluster/apps/n8n-mcp/n8n-mcp-server/app/network-policies.yaml
git commit -m "feat(litellm): add MCP gateway infrastructure (Phase 1)

Register bravesearch, agentmemory, victoriametrics as MCP servers in
LiteLLM config. Add bidirectional CNPs between LiteLLM and all 4 MCP
backends. Bump memory to 3072Mi for MCP proxy overhead. Interactive
users access MCP via existing WAN ingress (split DNS).

Ref #1142"
git push
```

- [ ] **Step 3: Run cluster-validator**

Wait for Flux reconciliation. Verify LiteLLM pod restarts successfully with new config.

______________________________________________________________________

## Task 5: Manual LiteLLM UI Steps (User Action Required)

> **STOP: This task requires the user to perform manual steps in the LiteLLM admin UI.**

- [ ] **Step 1: Register context7 via LiteLLM UI**

Navigate to LiteLLM admin UI → MCP Servers → Add Server:

- **Server name:** `context7`

- **URL:** `https://mcp.context7.com/mcp`

- **Transport:** `http`

- **Static headers:** `{"CONTEXT7_API_KEY": "<actual key value>"}`

- **Access groups:** `core`

- [ ] **Step 2: Register n8n-mcp via LiteLLM UI**

Navigate to LiteLLM admin UI → MCP Servers → Add Server:

- **Server name:** `n8n-mcp`

- **URL:** `http://n8n-mcp-server.n8n-mcp.svc:3000/mcp`

- **Transport:** `http`

- **Auth type:** `bearer_token`

- **Auth value:** `<actual token value>`

- **Access groups:** `interactive`

- [ ] **Step 3: Configure team → access group mapping**

For each team, add the appropriate MCP access groups:

| Team                            | Add Groups                             |
| ------------------------------- | -------------------------------------- |
| claude-agents-read              | `core`                                 |
| claude-agents-write             | `core`                                 |
| claude-agents-spruyt-labs-read  | `core`, `observability`                |
| claude-agents-spruyt-labs-write | `core`, `observability`                |
| claude-agents-spruyt-labs-sre   | `core`, `observability`                |
| coder-workspaces                | `core`, `observability`, `interactive` |
| local-dev-containers            | `core`, `observability`, `interactive` |

If team-level access groups are not supported, set per virtual key instead.

- [ ] **Step 4: Verify MCP server registration**

Run: `curl -s -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://litellm.litellm.svc.cluster.local:4000/v1/mcp/registry.json | jq '.servers | keys'`

Expected: All 5 servers listed (bravesearch, agentmemory, victoriametrics, context7, n8n-mcp).

- [ ] **Step 5: Verify per-server tool discovery**

For each server, test tool listing:

```bash
# From a pod with litellm access (e.g., kubectl exec into a debug pod)
curl -s http://litellm.litellm.svc.cluster.local:4000/bravesearch/mcp -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | jq '.result.tools[].name'
```

Repeat for `/agentmemory/mcp`, `/context7/mcp`, `/victoriametrics/mcp`, `/n8n-mcp/mcp`.

- [ ] **Step 6: Verify access group enforcement**

Test that a generic agent key (claude-agents-read) CANNOT reach victoriametrics or n8n-mcp:

```bash
curl -s http://litellm.litellm.svc.cluster.local:4000/victoriametrics/mcp -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $GENERIC_AGENT_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Expected: 403 or empty tool list.

- [ ] **Step 7: Verify LAN IngressRoute**

From local dev or Coder workspace:

```bash
curl -s https://litellm.${EXTERNAL_DOMAIN}/health/readiness
```

Expected: 200 OK.

______________________________________________________________________

## Task 6: Update Agent MCP ConfigMaps

**Files:**

- Modify: `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml`

- Modify: `cluster/apps/claude-agents-write/claude-agents/app/claude-mcp-config.yaml`

- Modify: `cluster/apps/claude-agents-spruyt-labs-read/claude-agents/app/claude-mcp-config.yaml`

- Modify: `cluster/apps/claude-agents-spruyt-labs-write/claude-agents/app/claude-mcp-config.yaml`

- Modify: `cluster/apps/claude-agents-spruyt-labs-sre/claude-agents/app/claude-mcp-config.yaml`

- [ ] **Step 1: Update generic namespace configs (claude-agents-read, claude-agents-write)**

Replace the full `mcp.json` content in both files with:

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

- [ ] **Step 2: Update spruyt-labs namespace configs (read/write/sre)**

Replace the full `mcp.json` content in all 3 files with:

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
    },
    "victoriametrics": {
      "type": "http",
      "url": "http://litellm.litellm.svc.cluster.local:4000/victoriametrics/mcp",
      "headers": { "Authorization": "Bearer $${ANTHROPIC_AUTH_TOKEN}" }
    }
  }
}
```

______________________________________________________________________

## Task 7: Update Kyverno Injection Policy

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`

- [ ] **Step 1: Remove CONTEXT7_API_KEY env injection**

In the `inject-shared-config` rule, remove the env entry at lines 231-235:

```yaml
                  - name: CONTEXT7_API_KEY
                    valueFrom:
                      secretKeyRef:
                        name: mcp-credentials
                        key: context7-api-key
```

- [ ] **Step 2: Remove AGENTMEMORY_URL env injection**

In the same rule, remove lines 236-237:

```yaml
                  - name: AGENTMEMORY_URL
                    value: "http://agentmemory.agentmemory.svc.cluster.local:3111"
```

- [ ] **Step 3: Remove AGENTMEMORY_SECRET env injection**

In the same rule, remove lines 238-239:

```yaml
                  - name: AGENTMEMORY_SECRET
                    value: "unused-cluster-internal"
```

- [ ] **Step 4: Update policy description**

In the metadata annotations (lines 12-27), remove references to "Context7 API key" and "agentmemory connection" from the description.

______________________________________________________________________

## Task 8: Update Interactive MCP Config (.mcp.json)

**Files:**

- Modify: `.mcp.json`

- [ ] **Step 1: Replace .mcp.json content**

Replace the full file with:

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

Key changes: All remote servers route through LiteLLM gateway via split DNS. One auth key replaces 3. `agentmemory` named entry overrides built-in stdio plugin (C10). `context7` built-in plugin will be uninstalled; LiteLLM gateway replaces it. `cclsp` stays stdio unchanged (C9).

______________________________________________________________________

## Task 9: Commit and Push Phase 2 Consumer Migration

- [ ] **Step 1: Run qa-validator**

Validate all modified files.

- [ ] **Step 2: Commit Phase 2**

```bash
git add \
  cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml \
  cluster/apps/claude-agents-write/claude-agents/app/claude-mcp-config.yaml \
  cluster/apps/claude-agents-spruyt-labs-read/claude-agents/app/claude-mcp-config.yaml \
  cluster/apps/claude-agents-spruyt-labs-write/claude-agents/app/claude-mcp-config.yaml \
  cluster/apps/claude-agents-spruyt-labs-sre/claude-agents/app/claude-mcp-config.yaml \
  cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml \
  .mcp.json
git commit -m "feat(litellm): migrate MCP consumers to gateway (Phase 2)

Point all agent MCP configs to LiteLLM per-server endpoints. Replace
agentmemory stdio with HTTP through gateway. Remove CONTEXT7_API_KEY,
AGENTMEMORY_URL, AGENTMEMORY_SECRET from Kyverno injection. Update
.mcp.json for interactive users to route through LiteLLM LAN ingress.

Ref #1142"
git push
```

- [ ] **Step 3: Run cluster-validator**

Verify Flux reconciliation. Check that agent pods and Kyverno policy update successfully.

______________________________________________________________________

## Task 10: End-to-End Verification

- [ ] **Step 1: Verify agent MCP tools**

Trigger a test agent job and verify all MCP tools are functional:

- agentmemory tools (memory_save, memory_recall)

- bravesearch tools (brave_web_search)

- context7 tools (resolve-library-id, query-docs)

- victoriametrics tools (query, metrics) — spruyt-labs agents only

- agentplatform tools (still direct, unchanged)

- [ ] **Step 2: Verify interactive MCP tools**

From this Coder workspace (after restart to pick up new .mcp.json):

- Test each MCP server connection

- Verify plugin suppression: agentmemory and context7 show as HTTP (not stdio)

- [ ] **Step 3: Verify guardrails don't interfere**

Test a VictoriaMetrics query containing IP addresses through the gateway. Verify Presidio PII masking doesn't corrupt the query.

- [ ] **Step 4: Monitor LiteLLM resources**

Run: `kubectl top pod -n litellm -l app.kubernetes.io/name=litellm`

Verify no OOMKill. Check VPA recommendations align with actual usage.

______________________________________________________________________

## Phase 3: Cleanup (Separate Issue)

> Phase 3 cleanup is tracked separately. Create a new issue after Phase 2 is validated. The cleanup removes:
>
> - Agent direct MCP CNPs (brave-search, agentmemory egress from shared base; victoriametrics from spruyt-labs)
> - Traefik MCP ingresses (brave-search-mcp, n8n-mcp, mcp-victoriametrics, agentmemory-mcp.lan)
> - Traefik MCP API keys SOPS secret + RBAC
> - Coder ExternalSecrets + SecretStores (5 files)
> - Coder template MCP API key env_from
> - Coder workspace direct MCP CNPs
> - n8n-mcp cross-namespace RBAC
> - `context7-api-key` from agents-shared `mcp-credentials.sops.yaml`
>
> Do NOT delete these before end-to-end validation. They serve as fallback during migration.
