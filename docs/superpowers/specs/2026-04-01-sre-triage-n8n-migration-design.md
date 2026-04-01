# SRE Alertmanager Triage — n8n + Claude Code CLI Migration

**Issue:** #823 Phase 2, Step 1
**Date:** 2026-04-01
**Status:** Draft

## Summary

Migrate the SRE Alertmanager triage function from OpenClaw to an n8n workflow + Claude Code CLI node. The agent investigates alerts using MCP tools (kubernetes, victoriametrics, discord, github) and returns structured JSON. n8n handles webhook reception, Discord posting (threads, replies), resolved alerts, and state management via Valkey.

## Architecture

```text
Alertmanager
    │
    ▼ (webhook POST, Header Auth)
n8n Webhook Node (n8n-system, port 5678)
    │
    ▼
IF: alertname = "Watchdog" → End (no-op, saves Claude Code invocation)
    │
    ▼
IF: status = "resolved"
    ├─ true → Valkey lookup thread_id → Post "resolved" in thread → Close thread → End
    └─ false ▼
Code Node: Format Alertmanager payload into Claude Code prompt
    │
    ▼
Claude Code CLI Node
    │  Model: Claude Opus 4.6
    │  MCP: kubernetes, victoriametrics, discord, github
    │  Namespace: claude-agents-read (read-only RBAC)
    │
    ▼
Structured JSON output
    │
    ▼
Code Node: Parse JSON
    │
    ▼
IF: skip = true → End
    │
    ▼
IF: alert_message_id != null
    ├─ true → Discord: Create thread on alertmanager message → Post triage in thread
    └─ false → Discord: Post standalone message to #k8s-alerts
    │
    ▼
Valkey: Store thread_id (key: sre:thread:<alertname>:<instance>:<startsAt>, TTL: 7 days)
    │
    ▼
IF: github_issue_url != null → Discord: Post issue link in thread
```

## Responsibility Split

### Claude Code CLI Agent

- **Situational awareness** — Read recent Discord messages via discord MCP to detect correlated alerts, maintenance context, existing triage
- **GitHub context** — Check open maintenance issues and recent Renovate PRs via github MCP
- **Investigation** — Query cluster state (kubernetes MCP) and metrics (victoriametrics MCP)
- **GitHub issue management** — Search for existing alert issues, create new or comment on existing
- **Structured output** — Return JSON for n8n to act on

### n8n Workflow

- **Webhook reception** — Receive Alertmanager POST with Header Auth
- **Watchdog filtering** — Skip Watchdog alerts before invoking Claude Code
- **Resolved alerts** — Look up Valkey thread mapping, post resolved message, close thread (no Claude Code invocation)
- **Discord posting** — Find alertmanager message, create threads, post triage reports, post issue links
- **State management** — Store/retrieve thread IDs in Valkey with 7-day TTL

## Output Contract

The Claude Code CLI node returns JSON:

```json
{
  "alert_message_id": "1234567890123456789",
  "alertname": "EtcdHighCommitDurations",
  "severity": "warning",
  "status": "firing",
  "skip": false,
  "maintenance_context": "Part of Talos node upgrade (ref #815)",
  "summary": "etcd commit durations elevated on node k8s-cp-1",
  "findings": [
    "etcd_disk_backend_commit_duration_seconds_bucket p99 at 0.35s (threshold 0.25s)",
    "Node k8s-cp-1 recently rebooted (uptime 12m)",
    "Other etcd members healthy"
  ],
  "probable_cause": "Post-reboot etcd compaction causing temporary elevated commit latency",
  "recommended_action": "Expected during node upgrade. Will self-resolve within ~30 minutes.",
  "confidence": "high",
  "create_issue": false,
  "github_issue_url": null,
  "thread_name": "EtcdHighCommitDurations triage — 14:30 UTC"
}
```

### Field Definitions

| Field | Type | Description |
| ----- | ---- | ----------- |
| `alert_message_id` | `string\|null` | Discord message ID of the Alertmanager bot message. `null` if not found (n8n posts standalone) |
| `alertname` | `string` | Alert name from payload |
| `severity` | `string` | Alert severity (critical, warning, info) |
| `status` | `string` | Always `firing` (resolved handled by n8n) |
| `skip` | `boolean` | `true` for transient/self-resolving alerts not worth posting |
| `maintenance_context` | `string\|null` | Correlation with ongoing maintenance, or `null` |
| `summary` | `string` | One-line summary of the alert condition |
| `findings` | `string[]` | Investigation findings, one per array element |
| `probable_cause` | `string` | Root cause assessment |
| `recommended_action` | `string` | Concrete next step or "no action needed" |
| `confidence` | `string` | `high`, `medium`, or `low` |
| `create_issue` | `boolean` | Whether a GitHub issue was created/commented |
| `github_issue_url` | `string\|null` | URL of created/commented issue, or `null` |
| `thread_name` | `string` | Suggested Discord thread name |

## MCP Configuration

Updated `claude-mcp-config` ConfigMap for `claude-agents-read` namespace:

```json
{
  "mcpServers": {
    "kubernetes": {
      "type": "http",
      "url": "http://kubectl-mcp-server.kubectl-mcp.svc:8000/mcp"
    },
    "victoriametrics": {
      "type": "http",
      "url": "http://mcp-victoriametrics.observability.svc:8080/mcp"
    },
    "github": {
      "type": "http",
      "url": "http://github-mcp-server.github-mcp.svc:8082/mcp",
      "headers": {
        "Authorization": "Bearer $${GITHUB_MCP_TOKEN}"
      }
    },
    "discord": {
      "type": "http",
      "url": "http://discord-mcp.discord-mcp.svc:8080/mcp"
    }
  }
}
```

### discord-mcp Deployment

discord-mcp (SaseQ/discord-mcp) is a Java/Docker MCP server that uses stdio transport. To integrate with the HTTP-based MCP config, it needs to be deployed as an HTTP service. Options:

1. **Check for HTTP flag** — Java MCP SDK often supports `--transport http` or similar
2. **Use supergateway/mcp-proxy** — Bridge stdio→HTTP with a thin wrapper
3. **HTTP wrapper deployment** — Deploy with a sidecar that converts stdio↔HTTP

The deployment will follow the same pattern as github-mcp-server: dedicated namespace, CiliumNetworkPolicy for agent pod egress.

### Network Policy Addition

Add to `claude-agents-read/claude-agents/app/network-policies.yaml`:

```yaml
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-discord-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: discord-mcp
            k8s:app.kubernetes.io/name: discord-mcp
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

## Agent System Prompt

Stored at: `cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md`

Adapted from the OpenClaw SRE agent (`anthony-spruyt/openclaw-workspace/workspaces/sre/AGENTS.md`).

### Key Adaptations from OpenClaw

| OpenClaw | Claude Code CLI |
| -------- | -------------- |
| `mcporter call kubectl-mcp.*` | `mcp__kubernetes__*` native tools |
| `mcporter call victoriametrics.*` | `mcp__victoriametrics__*` native tools |
| `message(action=read, channel=discord, ...)` | `mcp__discord__read_messages` |
| `message(action=send/thread-create/thread-reply, ...)` | Removed — n8n handles Discord writes |
| `gh issue list/create/comment` | `mcp__github__search_issues`, `mcp__github__create_issue`, `mcp__github__add_issue_comment` |
| Thread tracking (alert-threads.json) | Removed — n8n + Valkey handles |
| Watchdog skip logic | Removed — n8n filters before agent invocation |

### Prompt Structure

1. **Role** — SRE triage agent for spruyt-labs cluster. Terse, technical, evidence-based.
2. **Input** — Alertmanager webhook JSON payload (passed as prompt by n8n Code node).
3. **MCP tool reference** — Key tool mappings for kubernetes, victoriametrics, discord, github.
4. **Step 0: Situational awareness**
   - Read recent Discord #k8s-alerts messages via `mcp__discord__read_messages` — check for correlated alerts, maintenance context, existing triage
   - Check GitHub for open maintenance issues via `mcp__github__search_issues` and recent Renovate PRs via `mcp__github__list_pull_requests`
   - Correlate: if 3+ alerts in 30 minutes AND/OR active maintenance, lead with correlation finding
5. **Steps 1-7: Investigation** (carried over from OpenClaw)
   - Identify affected resource
   - Pod/workload state
   - Recent events
   - Node state
   - HelmRelease state
   - Flux kustomization state
   - Logs (if relevant)
   - Metrics (quantify the problem)
6. **GitHub issue management**
   - Search for existing open issues with `alert` label matching alertname
   - If found: comment with triage update
   - If not found and not maintenance noise: create new issue with `alert` + `sre` labels
   - Skip issue creation for expected maintenance noise
7. **Output** — Return structured JSON matching the output contract. Always output valid JSON and nothing else.
8. **Common mistakes** (carried over from OpenClaw)
   - Cilium: never use `analyze_network_policies` (K8s only, misses Cilium CRDs), always check both CNPs and CCNPs
   - Cluster-wide `allow-kube-dns-egress` CCNP covers all pods — never report "missing DNS egress"
   - Zero results may mean tooling/RBAC gap, not reality
   - Don't trust existing GitHub issues blindly — verify diagnosis
   - Low-rate drops (<1/s) that self-resolve don't need forensics

### Constraints

- Read-only cluster operations — no kubectl apply, delete, patch, exec, or restart
- Max 12 MCP investigation calls for single-alert payloads, 18 for multi-alert
- Must use at least one kubernetes MCP call AND one victoriametrics call per triage
- If an MCP server is unavailable, state explicitly as a gap in findings
- Discord reads and GitHub calls do not count toward investigation call limit

## n8n Workflow Template

Stored at: `cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json`

An importable n8n workflow JSON covering:

1. **Webhook trigger** — POST endpoint with Header Auth
2. **Watchdog filter** — IF node, `alertname != Watchdog`
3. **Resolved handler** — IF node on `status`, Valkey lookup, Discord post, thread close
4. **Prompt formatter** — Code node extracting key fields from Alertmanager payload
5. **Claude Code CLI node** — Opus model, system prompt from template, MCP config
6. **Output parser** — Code node parsing JSON response
7. **Skip filter** — IF node on `skip` field
8. **Discord thread creation** — Conditional on `alert_message_id`
9. **Discord triage post** — Format findings into Discord message
10. **Valkey store** — Save thread mapping with TTL
11. **GitHub issue link** — Conditional Discord post

### Valkey Key Pattern

- Key: `sre:thread:<alertname>:<instance>:<startsAt>`
- Value: Discord thread ID
- TTL: 604800 seconds (7 days)

Instance component priority (from alert labels):
1. `labels.instance`
2. `labels.pod`
3. `labels.deployment`
4. `labels.namespace`
5. Literal `cluster`

## Resolved Alert Flow (n8n Only)

No Claude Code invocation. Entirely handled by n8n:

1. Extract `alertname`, instance component, `startsAt` from payload
2. Build Valkey key: `sre:thread:<alertname>:<instance>:<startsAt>`
3. Lookup thread ID in Valkey
4. **If found:** Post resolved message in thread, close/archive thread, delete Valkey key
5. **If not found:** Post standalone resolved message to #k8s-alerts

Resolved message format:
```text
Resolved — <alertname>
Alert cleared at <endsAt>. No further action required.
```

## File Deliverables

| File | Purpose |
| ---- | ------- |
| `cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md` | Agent system prompt template |
| `cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json` | Importable n8n workflow |
| `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml` | Add discord MCP server |
| `cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml` | Add discord-mcp egress policy |

## Out of Scope

- Monitor agent / scheduled health check migration (Phase 2, Step 4)
- GitHub issue triage workflow (Phase 2, Step 2)
- Home Assistant events workflow (Phase 2, Step 3)
- OpenClaw decommission (Phase 3)

## Risks

- **discord-mcp HTTP transport** — May need a proxy/wrapper. If deployment blocks, the agent can operate without Discord reads (loses situational awareness, still functional for investigation + GitHub)
- **discord-mcp thread gap** — discord-mcp lacks thread creation/reply tools. n8n handles this via its Discord nodes, but the agent can't verify thread state during investigation
- **n8n Claude Code CLI node maturity** — Community node (v1.8.0, single maintainer). May need contributions for edge cases
- **Ephemeral pod MCP startup** — MCP server connections need to be established each invocation. HTTP transport (already in use) handles this well
