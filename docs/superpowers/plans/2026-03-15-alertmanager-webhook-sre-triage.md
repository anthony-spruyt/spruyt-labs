# Alertmanager Webhook → OpenClaw SRE Triage Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Alertmanager webhooks into OpenClaw so an SRE agent can investigate alerts and post structured triage reports to Discord.

**Architecture:** Alertmanager sends webhook POSTs to OpenClaw's `/hooks/alertmanager` endpoint (cluster-internal). A hook mapping routes alerts to a dedicated SRE agent (Sonnet 4.6) with per-alert sessions keyed by `groupKey`. Cilium network policy allows the traffic.

**Tech Stack:** OpenClaw (hooks/agents), VMAlertmanager, Cilium network policies, SOPS

**Spec:** [`docs/superpowers/specs/2026-03-15-alertmanager-webhook-sre-triage-design.md`](../specs/2026-03-15-alertmanager-webhook-sre-triage-design.md)
**Issue:** [#658](https://github.com/anthony-spruyt/spruyt-labs/issues/658)

---

## Chunk 1: Implementation

### Task 1: Add SRE agent and hooks config to `openclaw.json`

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/openclaw.json`

- [ ] **Step 1: Add SRE agent to `agents.list`**

In `cluster/apps/openclaw/openclaw/app/openclaw.json`, add a new entry to the `agents.list` array (after the existing `coordinator` entry at line 133):

```json
{
  "id": "sre",
  "model": {
    "primary": "anthropic/claude-sonnet-4-6",
    "fallbacks": ["openai/gpt-5-mini"]
  }
}
```

- [ ] **Step 2: Add `hooks` config block**

In the same file, add the `hooks` top-level key. Place it after the `plugins` block (after line 262, before the closing `}`). **Add a trailing comma after the `plugins` closing `}`** to keep the JSON valid:

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

- [ ] **Step 3: Validate JSON syntax**

Run: `python3 -m json.tool cluster/apps/openclaw/openclaw/app/openclaw.json > /dev/null`
Expected: No output (valid JSON)

- [ ] **Step 4: Validate against schema**

Run: `python3 -c "import json; d=json.load(open('cluster/apps/openclaw/openclaw/app/openclaw.json')); s=json.load(open('cluster/apps/openclaw/openclaw/app/openclaw-schema.json')); print('Schema loaded, keys:', len(s.get('properties',{})))"`
Expected: Schema loads without error. Full jsonschema validation is not required — the OpenClaw pod validates on startup.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/openclaw.json
git commit -m "feat(openclaw): add SRE agent and alertmanager webhook hooks

Ref #658"
```

### Task 2: Add Cilium network policy for alertmanager ingress

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/network-policies.yaml`

- [ ] **Step 1: Add network policy**

Append the following CiliumNetworkPolicy to the end of `cluster/apps/openclaw/openclaw/app/network-policies.yaml` (after the last `---` block for `allow-mcp-kubectl-egress`):

```yaml
---
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
            k8s:app.kubernetes.io/name: vmalertmanager
      toPorts:
        - ports:
            - port: "18789"
              protocol: TCP
```

> **Key detail:** The `k8s:` prefix is required for labels that Cilium reads from Kubernetes pod metadata (namespace and standard labels). Verified label: `app.kubernetes.io/name: vmalertmanager` (from live pod `vmalertmanager-victoria-metrics-k8s-stack-0`).

- [ ] **Step 2: Validate YAML syntax**

Run: `python3 -c "import yaml; list(yaml.safe_load_all(open('cluster/apps/openclaw/openclaw/app/network-policies.yaml'))); print('OK')"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/network-policies.yaml
git commit -m "feat(openclaw): add cilium policy for alertmanager webhook ingress

Ref #658"
```

### Task 3: Run qa-validator

- [ ] **Step 1: Run qa-validator agent**

Dispatch the `qa-validator` agent to validate all changes before the user pushes.

Expected: APPROVED

- [ ] **Step 2: Fix any issues and re-run if needed**

If qa-validator reports issues, fix them and re-run until APPROVED.

### Task 4: User edits alertmanager SOPS secret (manual — instructions only)

**Files:**
- Modify: `cluster/apps/observability/victoria-metrics-k8s-stack/app/victoria-metrics-k8s-stack-secrets.sops.yaml` (user edits manually via `sops`)

> **This task is for the user to perform manually.** The agent cannot edit SOPS files.

- [ ] **Step 1: Provide instructions to user**

Tell the user to edit the SOPS secret:

```bash
sops cluster/apps/observability/victoria-metrics-k8s-stack/app/victoria-metrics-k8s-stack-secrets.sops.yaml
```

Add this receiver to the `receivers:` list:

```yaml
- name: openclaw-sre
  webhook_configs:
    - url: http://openclaw-main.openclaw.svc.cluster.local:18789/hooks/alertmanager
      http_config:
        authorization:
          credentials: <paste OPENCLAW_HOOKS_TOKEN value from openclaw-secrets>
      send_resolved: true
      max_alerts: 10
```

Add this route as the **first entry** in `route.routes:`:

```yaml
- receiver: openclaw-sre
  matchers:
    - alertname!="Watchdog"
  continue: true
```

> **Important:** Place the route BEFORE existing routes. `continue: true` ensures alerts still flow to the existing Discord receiver.

- [ ] **Step 2: User commits the SOPS change**

```bash
git add cluster/apps/observability/victoria-metrics-k8s-stack/app/victoria-metrics-k8s-stack-secrets.sops.yaml
git commit -m "feat(observability): add openclaw-sre alertmanager receiver

Ref #658"
```

### Task 5: Post-push verification

> **Run after user pushes to main.**

- [ ] **Step 1: Run cluster-validator agent**

Dispatch the `cluster-validator` agent to verify Flux reconciliation succeeds.

- [ ] **Step 2: Verify OpenClaw hooks are registered**

Check OpenClaw pod logs for hook registration:

```bash
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw --tail=50 | grep -i hook
```

Expected: Log lines showing hooks system enabled and alertmanager mapping registered.

- [ ] **Step 3: Verify network policy is applied**

```bash
kubectl get ciliumnetworkpolicy -n openclaw allow-alertmanager-ingress
```

Expected: Policy exists and is applied.

- [ ] **Step 4: Check for Cilium policy drops**

Dispatch the `cnp-drop-investigator` agent targeting the `openclaw` namespace to verify no unintended drops.
