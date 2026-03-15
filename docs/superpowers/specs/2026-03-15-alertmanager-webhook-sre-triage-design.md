# Alertmanager Webhook → OpenClaw SRE Triage Agent

**Issue:** [#658](https://github.com/anthony-spruyt/spruyt-labs/issues/658)
**Date:** 2026-03-15

## Overview

Wire Alertmanager into OpenClaw's webhook ingress so that when an alert fires, a dedicated SRE agent investigates using kubectl-mcp and posts a structured triage report to Discord — rather than forwarding raw alerts.

## Architecture

```text
Alert fires
    │
    ▼
VMAlert evaluates rule
    │
    ▼
Alertmanager receives alert
    │
    ├──► Existing receiver (raw Discord)     ← unchanged, continue: true
    │
    └──► openclaw-sre receiver (NEW)
         │
         ▼
         POST http://openclaw-main.openclaw.svc.cluster.local:18789/hooks/alertmanager
         Authorization: Bearer <OPENCLAW_HOOKS_TOKEN>
         Body: Alertmanager webhook JSON payload
              │
              ▼
         OpenClaw hook mapping matches path "alertmanager"
              │
              ▼
         Routes to SRE agent session (keyed by groupKey)
              │
              ▼
         Agent investigates via kubectl-mcp + VictoriaMetrics MCP:
           - Pod logs, events, restart history
           - HelmRelease/Kustomization state
           - Metrics queries, alert history, resource usage
           - Recent Renovate/git activity
              │
              ▼
         Posts structured triage report to Discord channel 1473506635656990862

Alert resolves
    │
    ▼
         Same session receives resolved payload
              │
              ▼
         Agent posts brief all-clear with duration
```

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Transport | Cluster-internal URL | Both services in-cluster; avoids unnecessary Traefik/Cloudflare hops |
| Routing | Dual-route (continue: true) | Existing raw Discord alerts preserved; OpenClaw is additive |
| Alert scope | Everything except Watchdog | Start broad, tune matchers later as needed |
| Resolved alerts | send_resolved: true | Routes to same session via groupKey; agent posts contextual all-clear |
| Session routing | Per-alert via groupKey | `sessionKey: "hook:sre:{{groupKey}}"` — firing + resolved hit same session |
| Token sync | Baked into alertmanager SOPS secret | Token must be literal in alertmanager config YAML; ExternalSecret adds complexity without benefit |
| SRE agent model | Sonnet 4.6 | Capable enough for investigation/reasoning, cost-effective for frequent alerts |
| Agent choice | New `sre` agent (not `monitor`) | Issue #658 originally proposed `monitor` (haiku). Changed to dedicated `sre` agent with Sonnet — haiku lacks reasoning depth for triage; dedicated agent allows independent system prompt and model tuning |
| Hook message | Minimal | Pass through alert payload with brief instruction; SRE agent's system prompt (created separately) defines triage methodology |
| allowedAgentIds | ["sre"] only | Scoped to the SRE agent |
| Hook presets | Manual mapping (no preset) | OpenClaw's `presets` field only has `gmail` built-in; no `alertmanager` preset exists |

## Changes

### 1. `openclaw.json` — Add `hooks` config and SRE agent

Add the `hooks` top-level block:

```json
"hooks": {
  "enabled": true,
  "token": "${OPENCLAW_HOOKS_TOKEN}",
  "allowedAgentIds": ["sre"],
  "mappings": [
    {
      "id": "alertmanager",
      "match": {
        "path": "alertmanager"
      },
      "action": "agent",
      "agentId": "sre",
      "sessionKey": "hook:sre:{{groupKey}}",
      "messageTemplate": "Alertmanager webhook received. Triage this alert.",
      "deliver": true,
      "channel": "discord"
    }
  ]
}
```

Add SRE agent to `agents.list`:

```json
{
  "id": "sre",
  "model": {
    "primary": "anthropic/claude-sonnet-4-6",
    "fallbacks": ["openai/gpt-5-mini"]
  }
}
```

### 2. Alertmanager config (SOPS secret — user edits manually)

In `victoria-metrics-k8s-stack-secrets.sops.yaml`, add to the alertmanager config:

**New receiver:**

```yaml
receivers:
  # ... existing receivers ...
  - name: openclaw-sre
    webhook_configs:
      - url: http://openclaw-main.openclaw.svc.cluster.local:18789/hooks/alertmanager
        http_config:
          authorization:
            credentials: <OPENCLAW_HOOKS_TOKEN value>
        send_resolved: true
        max_alerts: 10
```

**New route (add BEFORE existing routes so it fires first):**

```yaml
route:
  routes:
    - receiver: openclaw-sre
      matchers:
        - alertname!="Watchdog"
      continue: true
    # ... existing routes ...
```

> **Note:** `continue: true` means Alertmanager continues matching subsequent routes after this one. Place the openclaw-sre route first to guarantee it fires regardless of whether existing routes have `continue`.

### 3. `network-policies.yaml` — Alertmanager ingress

New CiliumNetworkPolicy allowing ingress from `observability` namespace (vmalertmanager) to OpenClaw on port 18789:

```yaml
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Alertmanager (observability namespace)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-alertmanager-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: openclaw
      app.kubernetes.io/name: openclaw
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            app: vmalertmanager
      toPorts:
        - ports:
            - port: "18789"
              protocol: TCP
```

> **Note:** The vmalertmanager pod label selector needs verification against the actual pod labels in cluster. The victoria-metrics-operator creates pods with labels like `app: vmalertmanager` but this should be confirmed.

## Files Changed

| File | Change |
|------|--------|
| `cluster/apps/openclaw/openclaw/app/openclaw.json` | Add `hooks` config block + SRE agent to `agents.list` |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/victoria-metrics-k8s-stack-secrets.sops.yaml` | Add webhook receiver + route (**user edits SOPS manually**) |
| `cluster/apps/openclaw/openclaw/app/network-policies.yaml` | Add alertmanager→openclaw ingress policy |

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| **Flapping alerts** — rapid fire/resolve cycles consume model tokens | OpenClaw's session-per-groupKey naturally deduplicates: re-firings with the same groupKey reuse the existing session. Alertmanager's `group_wait`/`group_interval`/`repeat_interval` also batch alerts before sending. |
| **Token duplication** — same token in two SOPS files (`openclaw-secrets` and `victoria-metrics-k8s-stack-secrets`) | Manual sync required on rotation. Document this in the alertmanager SOPS file with a comment referencing the openclaw source. |
| **max_alerts: 10 truncation** — grouped alerts exceeding 10 may lose context | Acceptable trade-off to keep payload size manageable. The `truncatedAlerts` field in the payload indicates if alerts were dropped. Increase if SRE agent reports incomplete investigations. |

## Out of Scope

- **SRE agent system prompt** — user creates separately; defines triage methodology, tool usage, report format
- **Token value management** — `OPENCLAW_HOOKS_TOKEN` already added to `openclaw-secrets.sops.yaml`
- **Alert tuning** — route matchers start broad; refined based on operational experience

## Verification

1. After push, confirm OpenClaw pod restarts with hooks enabled (check logs for hook registration)
2. Trigger a test alert or wait for a natural firing
3. Verify Discord channel receives structured triage report (not just raw alert)
4. Verify resolved alerts post all-clear to the same Discord thread
5. Confirm Cilium network policy allows alertmanager→openclaw traffic (check for policy drops)
