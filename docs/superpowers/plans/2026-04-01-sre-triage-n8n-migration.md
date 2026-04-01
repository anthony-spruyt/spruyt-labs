# SRE Alertmanager Triage — n8n Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the SRE triage system prompt, n8n workflow template, and deploy discord-mcp server for Alertmanager alert triage via Claude Code CLI, replacing the OpenClaw SRE agent.

**Architecture:** n8n webhook receives Alertmanager alerts, filters Watchdog/resolved, invokes Claude Code CLI with SRE prompt and 4 MCP servers (kubernetes, victoriametrics, discord, github). Agent investigates and returns structured JSON. n8n handles Discord thread posting and Valkey state.

**Tech Stack:** n8n workflow JSON, Claude Code CLI system prompt (markdown), Kubernetes YAML (ConfigMap, CiliumNetworkPolicy, HelmRelease), Dockerfile, GitHub Actions

---

## File Structure

| File | Action | Responsibility |
| ---- | ------ | -------------- |
| `cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md` | Create | Agent system prompt template for Claude Code CLI node |
| `cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json` | Create | Importable n8n workflow template |
| `cluster/apps/discord-mcp/namespace.yaml` | Create | Namespace with PSA labels |
| `cluster/apps/discord-mcp/kustomization.yaml` | Create | Namespace kustomization |
| `cluster/apps/discord-mcp/discord-mcp/ks.yaml` | Create | Flux Kustomization |
| `cluster/apps/discord-mcp/discord-mcp/app/kustomization.yaml` | Create | App kustomization |
| `cluster/apps/discord-mcp/discord-mcp/app/release.yaml` | Create | HelmRelease (app-template) |
| `cluster/apps/discord-mcp/discord-mcp/app/values.yaml` | Create | Deployment values (supergateway + discord-mcp) |
| `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml` | Create | Cilium network policies |
| `cluster/apps/discord-mcp/discord-mcp/app/vpa.yaml` | Create | VPA recommendation-only |
| `cluster/apps/discord-mcp/discord-mcp/app/discord-secrets.sops.yaml` | Create | SOPS-encrypted Discord bot token |
| `images/discord-mcp/Dockerfile` | Create | Wrapper image: supergateway + discord-mcp |
| `.github/workflows/release-discord-mcp.yaml` | Create | Build and push wrapper image to GHCR |
| `cluster/apps/kustomization.yaml` | Modify | Register discord-mcp namespace |
| `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml` | Modify | Add discord MCP server entry |
| `cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml` | Modify | Add discord-mcp egress policy |
| `cluster/apps/n8n-system/n8n/app/network-policies.yaml` | Already done | Alertmanager ingress (committed in 542afc3c) |

---

### Task 1: Create SRE Triage System Prompt

**Files:**
- Create: `cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md`

- [ ] **Step 1: Create assets directory**

```bash
mkdir -p cluster/apps/n8n-system/n8n/assets
```

- [ ] **Step 2: Write the SRE triage system prompt**

Create `cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md` with the full agent prompt. The prompt is adapted from the OpenClaw SRE agent (`anthony-spruyt/openclaw-workspace/workspaces/sre/AGENTS.md`).

Key sections to include:

**Role:**
```text
You are an SRE triage agent for the spruyt-labs Kubernetes cluster. Terse. Technical. Evidence-based. Every claim backed by actual cluster data — MCP tool output, metrics queries, log lines. Never speculate without data.
```

**Input specification:**
- Agent receives Alertmanager webhook JSON payload as the prompt
- Payload contains: `status`, `groupLabels`, `commonLabels`, `commonAnnotations`, `alerts[]` array
- Each alert has: `labels.alertname`, `labels.severity`, `annotations.description`, `startsAt`

**MCP tool reference — exact tool names the agent will see:**

| Purpose | MCP Tool |
| ------- | -------- |
| Get pods | `mcp__kubernetes__get_pods` |
| Get nodes | `mcp__kubernetes__get_nodes` |
| Get events | `mcp__kubernetes__get_events` |
| Get logs | `mcp__kubernetes__get_logs` |
| Describe resource | `mcp__kubernetes__kubectl_describe` |
| Generic kubectl | `mcp__kubernetes__kubectl_generic` |
| Get deployments | `mcp__kubernetes__get_deployments` |
| Get statefulsets | `mcp__kubernetes__get_statefulsets` |
| Get daemonsets | `mcp__kubernetes__get_daemonsets` |
| HelmRelease status | `mcp__kubernetes__get_custom_resource` |
| Kustomization status | `mcp__kubernetes__get_custom_resource` |
| Cilium policies | `mcp__kubernetes__cilium_policies_list_tool` |
| Hubble flows | `mcp__kubernetes__hubble_flows_query_tool` |
| Metrics query | `mcp__victoriametrics__query` |
| Range query | `mcp__victoriametrics__query_range` |
| Read Discord messages | `mcp__discord__read_messages` |
| Search GitHub issues | `mcp__github__search_issues` |
| Read GitHub issue | `mcp__github__issue_read` |
| Create/update issue | `mcp__github__issue_write` |
| Comment on issue | `mcp__github__add_issue_comment` |
| List PRs | `mcp__github__list_pull_requests` |

**Step 0 — Situational Awareness (mandatory, always first):**

A. Discord — read recent messages from #k8s-alerts channel:
```text
mcp__discord__read_messages(channelId="1403996226046787634", limit=30)
```
Look for: other recent alerts (correlated storm?), maintenance context, previous triage.

B. GitHub — check for active maintenance issues:
```text
mcp__github__search_issues(query="repo:anthony-spruyt/spruyt-labs state:open talos OR upgrade OR renovate batch", owner="anthony-spruyt", repo="spruyt-labs")
```
Also check recent Renovate PRs:
```text
mcp__github__list_pull_requests(owner="anthony-spruyt", repo="spruyt-labs", state="all", author="renovate[bot]")
```

C. Correlate — if 3+ alerts within 30 minutes AND/OR active maintenance, lead triage with correlation finding and single root cause assessment.

**Steps 1-7 — Investigation checklist:**
1. Identify — what fired, what namespace/service/pod is affected
2. Pod/workload state — running? CrashLoopBackOff? OOMKilled? Pending?
3. Recent events — events for the affected namespace
4. Node state — NotReady, cordoned, upgrading?
5. HelmRelease/Flux state — Ready? Recent upgrades, rollbacks, reconciliation failures?
6. Logs — recent container logs if relevant
7. Metrics — query relevant time-series to quantify the problem and understand trends

Must use at least one `mcp__kubernetes__*` call AND one `mcp__victoriametrics__*` call per triage.

**GitHub issue management:**

Search for existing open issue:
```text
mcp__github__search_issues(query="repo:anthony-spruyt/spruyt-labs state:open label:alert <alertname>")
```
Post-filter results to verify title contains the exact alertname.

If found — comment with triage update via `mcp__github__add_issue_comment`.

If not found and not maintenance noise — create via `mcp__github__issue_write`:
- Title: `<emoji> <alertname> — <brief description>` (emoji: fire for critical, warning for warning, info for info)
- Labels: `alert`, `sre`
- Body: structured triage report (trigger, severity, time, findings, probable cause, recommended action, confidence)

If maintenance noise — skip issue creation, set `create_issue: false` in output.

**Discord message identification:**

From Step 0's Discord read, find the Alertmanager bot message matching this alert:
- Look for a message where the embed title starts with `[FIRING` and contains the alertname
- Must be within the last 30 minutes (ignore stale matches)
- Take the most recent match (messages returned newest-first)
- Extract the message `id` and return as `alert_message_id`
- If no match found, set `alert_message_id: null`

**Output — structured JSON:**

Always output valid JSON and nothing else. No markdown, no commentary, no explanation outside the JSON. The JSON must match this schema exactly:

```json
{
  "alert_message_id": "<discord message id or null>",
  "alertname": "<string>",
  "severity": "<critical|warning|info>",
  "status": "firing",
  "skip": false,
  "maintenance_context": "<string or null>",
  "summary": "<one-line summary>",
  "findings": ["<finding 1>", "<finding 2>"],
  "probable_cause": "<root cause assessment>",
  "recommended_action": "<concrete next step>",
  "confidence": "<high|medium|low>",
  "create_issue": false,
  "github_issue_url": "<url or null>",
  "thread_name": "<alertname> triage — <HH:MM UTC>"
}
```

**Common mistakes section (carried from OpenClaw):**

Cilium investigation:
- NEVER use `mcp__kubernetes__analyze_network_policies` — only checks K8s NetworkPolicy, not Cilium CRDs
- Use `mcp__kubernetes__kubectl_generic` with `command=get ciliumnetworkpolicies -n <namespace> -o yaml`
- Always check BOTH namespace CNPs AND cluster-wide CCNPs
- Cluster-wide `allow-kube-dns-egress` CCNP covers all pods — never report "missing DNS egress"

Drop classification:
- Empty/null destination = external/world traffic (egress to internet)
- Empty/null source = external/world traffic inbound
- Named namespace = cross-namespace traffic
- `POLICY_DENIED` = no matching allow rule
- `STALE_OR_UNROUTABLE_IP` = transient from pod restarts
- 0-5 drops/hour is normal pod churn — do not overreact

Zero results:
- "Zero results" may mean tooling/RBAC gap, not reality
- Never conclude "no policies exist" without checking both CNPs and CCNPs
- State gaps explicitly rather than concluding nothing exists

Existing issues:
- Do NOT blindly trust existing GitHub issues — verify diagnosis against current cluster state

Transient alerts:
- Low-rate drops (<1/s) that self-resolve don't need forensics or GitHub issues
- Check metrics history first — if rate is already declining, keep triage brief

**Constraints:**
- Read-only cluster operations — no kubectl apply, delete, patch, exec, or restart
- Max 12 MCP investigation calls for single-alert payloads, 18 for multi-alert
- Discord reads and GitHub calls do not count toward this limit
- If an MCP server is unavailable, state explicitly as a gap in findings

- [ ] **Step 3: Verify the prompt file is well-formed markdown**

```bash
wc -l cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md
# Should be 200-400 lines
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md
git commit -m "feat(n8n): add SRE triage system prompt for Claude Code CLI

Ref #823"
```

---

### Task 2: Create n8n Workflow Template

**Files:**
- Create: `cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json`

This is an importable n8n workflow JSON. n8n workflows are JSON with a specific schema: `nodes[]`, `connections`, `settings`. The user imports this as a starting template and configures credentials in the UI.

- [ ] **Step 1: Write the n8n workflow JSON**

Create `cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json`.

The workflow contains these nodes (each with a unique `id`, `name`, `type`, `position`, and `parameters`):

**Node 1: Webhook Trigger**
- Type: `n8n-nodes-base.webhook`
- HTTP Method: POST
- Path: (user configures — matches Alertmanager webhook URL path)
- Authentication: Header Auth
- Response Mode: `lastNode` (respond after workflow completes)

**Node 2: Watchdog Filter**
- Type: `n8n-nodes-base.if`
- Condition: `{{ $json.alerts[0].labels.alertname }}` is not equal to `Watchdog`
- True output → Node 3
- False output → Node: No Operation (end)

**Node 3: Status Router**
- Type: `n8n-nodes-base.if`
- Condition: `{{ $json.status }}` equals `resolved`
- True output → Node 4 (Resolved flow)
- False output → Node 6 (Firing flow)

**Node 4: Build Valkey Key (Resolved)**
- Type: `n8n-nodes-base.code`
- JavaScript:

```javascript
const alerts = $input.first().json.alerts || [];
const alert = alerts[0] || {};
const labels = alert.labels || {};
const instance = labels.instance || labels.pod || labels.deployment || labels.namespace || 'cluster';
const alertname = labels.alertname || 'unknown';
const startsAt = alert.startsAt || '';
const key = `sre:thread:${alertname}:${instance}:${startsAt}`;
const endsAt = alert.endsAt || new Date().toISOString();
return [{ json: { key, alertname, endsAt } }];
```

**Node 5: Valkey Lookup + Discord Resolve + Close Thread**
- Type: `n8n-nodes-base.redis` (Valkey-compatible)
- Operation: Get
- Key: `{{ $json.key }}`
- On success → Discord send message to thread: `Resolved — {{ $json.alertname }}\nAlert cleared at {{ $json.endsAt }}.`
- Then delete key, close/archive thread
- On miss → Discord send standalone: `RESOLVED: {{ $json.alertname }} — cleared at {{ $json.endsAt }}`

**Node 6: Format Prompt (Firing)**
- Type: `n8n-nodes-base.code`
- JavaScript:

```javascript
const payload = $input.first().json;
const prompt = `Alertmanager webhook received. Triage this alert.

${JSON.stringify(payload, null, 2)}`;
return [{ json: { prompt } }];
```

**Node 7: Claude Code CLI**
- Type: `n8n-nodes-claude-code-cli.claudeCode`
- Prompt: `{{ $json.prompt }}`
- System Prompt: (paste from sre-triage-prompt.md)
- Model: `claude-opus-4-6`
- Output Format: `json`
- MCP Config: (configured via credentials/settings in UI)
- Timeout: 300000 (5 minutes)

**Node 8: Parse Output**
- Type: `n8n-nodes-base.code`
- JavaScript:

```javascript
const raw = $input.first().json.output || $input.first().json.text || '{}';
let result;
try {
  result = JSON.parse(typeof raw === 'string' ? raw : JSON.stringify(raw));
} catch (e) {
  result = {
    alert_message_id: null,
    alertname: 'parse_error',
    severity: 'warning',
    status: 'firing',
    skip: false,
    maintenance_context: null,
    summary: 'Failed to parse Claude Code output',
    findings: [`Raw output: ${String(raw).substring(0, 500)}`],
    probable_cause: 'Claude Code returned non-JSON output',
    recommended_action: 'Check agent prompt and MCP connectivity',
    confidence: 'low',
    create_issue: false,
    github_issue_url: null,
    thread_name: `parse-error triage — ${new Date().toISOString().substring(11, 16)} UTC`
  };
}
return [{ json: result }];
```

**Node 9: Skip Filter**
- Type: `n8n-nodes-base.if`
- Condition: `{{ $json.skip }}` equals `false`
- True output → Node 10
- False output → No Operation (end)

**Node 10: Thread or Standalone Router**
- Type: `n8n-nodes-base.if`
- Condition: `{{ $json.alert_message_id }}` is not empty
- True output → Node 11 (Create thread)
- False output → Node 12 (Standalone message)

**Node 11: Discord Create Thread + Post Triage**
- Type: `n8n-nodes-base.discord` (or HTTP Request to Discord API)
- Action: Create thread on message `{{ $json.alert_message_id }}`
- Thread name: `{{ $json.thread_name }}`
- Then post triage message in thread (formatted from findings)

**Node 12: Discord Standalone Message**
- Type: `n8n-nodes-base.discord`
- Channel: `1403996226046787634`
- Message: Formatted triage (summary + findings)

**Node 13: Format Discord Triage Message**
- Type: `n8n-nodes-base.code`
- JavaScript:

```javascript
const d = $input.first().json;
let msg = '';
if (d.maintenance_context) {
  msg += `**Context:**\n- ${d.maintenance_context}\n\n`;
}
msg += `**What fired:**\n- ${d.summary}\n\n`;
msg += `**Investigation:**\n`;
(d.findings || []).forEach(f => { msg += `- ${f}\n`; });
msg += `\n**Probable cause:**\n${d.probable_cause}\n\n`;
msg += `**Recommended action:**\n${d.recommended_action}\n\n`;
msg += `**Confidence:** ${d.confidence}`;

// Discord 2000 char limit
if (msg.length > 1950) {
  msg = msg.substring(0, 1947) + '...';
}
return [{ json: { ...d, discord_message: msg } }];
```

**Node 14: Store Thread ID in Valkey**
- Type: `n8n-nodes-base.redis`
- Operation: Set
- Key: built from alertname + instance + startsAt (same pattern as Node 4)
- Value: thread ID from Node 11 output
- TTL: 604800 (7 days)

**Node 15: Post GitHub Issue Link (conditional)**
- Type: `n8n-nodes-base.if` + `n8n-nodes-base.discord`
- Condition: `{{ $json.github_issue_url }}` is not empty
- Action: Post `Tracking issue: {{ $json.github_issue_url }}` in the thread

**Connections:** Wire nodes following the architecture diagram from the spec.

- [ ] **Step 2: Validate the JSON is syntactically valid**

```bash
python3 -c "import json; json.load(open('cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json'))" && echo "Valid JSON"
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json
git commit -m "feat(n8n): add SRE triage workflow template for import

Ref #823"
```

---

### Task 3: Build discord-mcp Wrapper Image

**Files:**
- Create: `images/discord-mcp/Dockerfile`
- Create: `.github/workflows/release-discord-mcp.yaml`

The discord-mcp server (SaseQ/discord-mcp) only supports stdio transport. We wrap it with supergateway to expose it as Streamable HTTP. This pattern (supergateway + init container) is reusable for any future stdio-only MCP server.

- [ ] **Step 1: Create the Dockerfile**

```bash
mkdir -p images/discord-mcp
```

Create `images/discord-mcp/Dockerfile`:

```dockerfile
# renovate: depName=saseq/discord-mcp datasource=docker
FROM saseq/discord-mcp:1.5.1 AS mcp-server

FROM node:22-alpine

# Install Java runtime (discord-mcp is a Spring Boot Java app)
RUN apk add --no-cache openjdk17-jre-headless

# renovate: depName=supergateway datasource=npm
ARG SUPERGATEWAY_VERSION=0.2.2
RUN npm install -g supergateway@${SUPERGATEWAY_VERSION}

# Copy the MCP server jar from the discord-mcp image
COPY --from=mcp-server /app/app.jar /app/app.jar

USER 1000

# Supergateway wraps the stdio MCP server and exposes it as Streamable HTTP
# Default port 8080, health endpoint at /healthz, MCP endpoint at /mcp
EXPOSE 8080

ENTRYPOINT ["supergateway", \
  "--stdio", "java -jar /app/app.jar", \
  "--outputTransport", "streamableHttp", \
  "--port", "8080", \
  "--healthEndpoint", "/healthz"]
```

- [ ] **Step 2: Create the GitHub Actions workflow**

Create `.github/workflows/release-discord-mcp.yaml`. Follow the pattern from `release-shutdown-orchestrator.yaml` but simplified for a Docker-only build (no Go compilation):

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/SchemaStore/schemastore/master/src/schemas/json/github-workflow.json
name: "Release Discord MCP"
on:
  workflow_dispatch:
    inputs:
      bump:
        description: "Version bump type"
        required: true
        type: "choice"
        options:
          - "patch"
          - "minor"
          - "major"
permissions:
  contents: "write"
  packages: "write"
  id-token: "write"
  attestations: "write"
env:
  IMAGE: "ghcr.io/anthony-spruyt/discord-mcp"
  WORKDIR: "images/discord-mcp"
  TAG_PREFIX: "discord-mcp/v"
jobs:
  resolve-version:
    name: "Resolve version"
    runs-on: "ubuntu-latest"
    outputs:
      tag: "${{ steps.bump.outputs.tag }}"
      version: "${{ steps.bump.outputs.version }}"
    steps:
      - name: "Checkout"
        uses: "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd" # v6
        with:
          fetch-depth: 0
          fetch-tags: true
      - name: "Compute next version"
        id: "bump"
        env:
          BUMP: "${{ inputs.bump }}"
        run: |
          LATEST=$(git tag --list "${TAG_PREFIX}*" --sort=-v:refname | head -1)
          if [ -z "$LATEST" ]; then
            NEXT="0.1.0"
          else
            VER=${LATEST#${TAG_PREFIX}}
            IFS='.' read -r MAJOR MINOR PATCH <<< "$VER"
            case "$BUMP" in
              major) NEXT="$((MAJOR+1)).0.0" ;;
              minor) NEXT="${MAJOR}.$((MINOR+1)).0" ;;
              patch) NEXT="${MAJOR}.${MINOR}.$((PATCH+1))" ;;
            esac
          fi
          echo "version=${NEXT}" >> "$GITHUB_OUTPUT"
          echo "tag=${TAG_PREFIX}${NEXT}" >> "$GITHUB_OUTPUT"
  build-and-push:
    name: "Build and push"
    needs: "resolve-version"
    runs-on: "ubuntu-latest"
    steps:
      - name: "Checkout"
        uses: "actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd" # v6
      - name: "Set up Docker Buildx"
        uses: "docker/setup-buildx-action@4d04d5d9486b7bd6fa91e7baf45bbb4f8b9deedd" # v4
      - name: "Login to GHCR"
        uses: "docker/login-action@b45d80f862d83dbcd57f89517bcf500b2ab88fb2" # v4
        with:
          registry: "ghcr.io"
          username: "${{ github.actor }}"
          password: "${{ secrets.GITHUB_TOKEN }}"
      - name: "Build and push"
        id: "push"
        uses: "docker/build-push-action@d08e5c354a6adb9ed34480a06d141179aa583294" # v7
        with:
          context: "${{ env.WORKDIR }}"
          push: true
          tags: |
            ${{ env.IMAGE }}:${{ needs.resolve-version.outputs.version }}
            ${{ env.IMAGE }}:latest
          platforms: "linux/amd64"
      - name: "Attest"
        uses: "actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32" # v4
        with:
          subject-name: "${{ env.IMAGE }}"
          subject-digest: "${{ steps.push.outputs.digest }}"
          push-to-registry: true
      - name: "Create tag"
        run: |
          git tag "${{ needs.resolve-version.outputs.tag }}"
          git push origin "${{ needs.resolve-version.outputs.tag }}"
```

- [ ] **Step 3: Commit**

```bash
git add images/discord-mcp/Dockerfile .github/workflows/release-discord-mcp.yaml
git commit -m "feat(discord-mcp): add wrapper image Dockerfile and CI workflow

Supergateway wraps the stdio-only discord-mcp server as Streamable HTTP.
This pattern is reusable for any future stdio-only MCP server.

Ref #823"
```

---

### Task 4: Deploy discord-mcp to Cluster

**Files:**
- Create: `cluster/apps/discord-mcp/namespace.yaml`
- Create: `cluster/apps/discord-mcp/kustomization.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/ks.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/kustomization.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/kustomizeconfig.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/release.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/values.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/vpa.yaml`
- Create: `cluster/apps/discord-mcp/discord-mcp/app/discord-secrets.sops.yaml`

Follow the github-mcp-server pattern exactly.

- [ ] **Step 1: Create namespace**

Create `cluster/apps/discord-mcp/namespace.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: discord-mcp
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 2: Create namespace kustomization**

Create `cluster/apps/discord-mcp/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./discord-mcp/ks.yaml
```

- [ ] **Step 3: Create Flux Kustomization**

Create `cluster/apps/discord-mcp/discord-mcp/ks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app discord-mcp
  namespace: flux-system
spec:
  targetNamespace: discord-mcp
  path: ./cluster/apps/discord-mcp/discord-mcp/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 4: Create app kustomization**

Create `cluster/apps/discord-mcp/discord-mcp/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
  - ./network-policies.yaml
  - ./vpa.yaml
  - ./discord-secrets.sops.yaml
configMapGenerator:
  - name: discord-mcp-values
    namespace: discord-mcp
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 5: Create kustomizeconfig**

Create `cluster/apps/discord-mcp/discord-mcp/app/kustomizeconfig.yaml`:

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

- [ ] **Step 6: Create HelmRelease**

Create `cluster/apps/discord-mcp/discord-mcp/app/release.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: discord-mcp
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: discord-mcp-values
```

- [ ] **Step 7: Create values.yaml**

Create `cluster/apps/discord-mcp/discord-mcp/app/values.yaml`:

```yaml
---
# Default values: https://github.com/bjw-s-labs/helm-charts/blob/main/charts/library/common/values.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/heads/main/charts/library/common/values.schema.json
defaultPodOptions:
  priorityClassName: low-priority
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
controllers:
  discord-mcp:
    strategy: Recreate
    containers:
      app:
        image:
          repository: ghcr.io/anthony-spruyt/discord-mcp
          tag: "0.1.0"
          pullPolicy: IfNotPresent
        env:
          - name: DISCORD_TOKEN
            valueFrom:
              secretKeyRef:
                name: discord-mcp-secrets
                key: DISCORD_TOKEN
          - name: DISCORD_GUILD_ID
            valueFrom:
              secretKeyRef:
                name: discord-mcp-secrets
                key: DISCORD_GUILD_ID
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            cpu: 10m
            memory: 128Mi
          limits:
            memory: 512Mi
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /healthz
                port: 8080
              initialDelaySeconds: 30
              periodSeconds: 30
              timeoutSeconds: 5
              failureThreshold: 3
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /healthz
                port: 8080
              initialDelaySeconds: 15
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
          startup:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /healthz
                port: 8080
              failureThreshold: 30
              periodSeconds: 5
persistence:
  tmp:
    type: emptyDir
    globalMounts:
      - path: /tmp
service:
  app:
    controller: discord-mcp
    ports:
      http:
        port: 8080
```

- [ ] **Step 8: Create network policies**

Create `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to Discord API
# DNS egress with L7 rule required for toFQDNs to populate Cilium's FQDN cache
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-discord-api-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: discord-mcp
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s:k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*"
    - toFQDNs:
        - matchName: discord.com
        - matchName: gateway.discord.gg
        - matchPattern: "*.discord.com"
        - matchPattern: "*.discord.gg"
        - matchPattern: "*.discord.media"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agent read pods
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-read-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: discord-mcp
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-read
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agent write pods
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-write-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: discord-mcp
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-write
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

- [ ] **Step 9: Create VPA**

Create `cluster/apps/discord-mcp/discord-mcp/app/vpa.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: discord-mcp
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: discord-mcp
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 512Mi
```

- [ ] **Step 10: Create SOPS secret placeholder**

The user needs to create this file manually with `sops`:

```bash
sops cluster/apps/discord-mcp/discord-mcp/app/discord-secrets.sops.yaml
```

With content:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: discord-mcp-secrets
stringData:
  DISCORD_TOKEN: "<bot-token>"
  DISCORD_GUILD_ID: "<guild-id>"
```

**Note:** This step is manual — the implementer should remind the user to create this file.

- [ ] **Step 11: Register namespace in Flux**

Add `discord-mcp` to `cluster/apps/kustomization.yaml` (the top-level apps kustomization that lists all app namespaces). Add the entry alongside the existing `github-mcp` entry:

```yaml
  - ./discord-mcp
```

- [ ] **Step 12: Commit**

```bash
git add cluster/apps/discord-mcp/
git commit -m "feat(discord-mcp): deploy discord MCP server with supergateway HTTP wrapper

Ref #823"
```

---

### Task 5: Add Discord MCP to Agent Runner Config

**Files:**
- Modify: `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml`

- [ ] **Step 1: Add discord MCP server entry**

In `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml`, add the `discord` entry to the `mcpServers` object:

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-mcp-config
data:
  mcp.json: |
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

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "
import yaml, json
with open('cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml') as f:
    doc = yaml.safe_load(f)
config = json.loads(doc['data']['mcp.json'])
assert 'discord' in config['mcpServers'], 'discord server not found'
print('Valid — discord MCP configured at', config['mcpServers']['discord']['url'])
"
```

Expected: `Valid — discord MCP configured at http://discord-mcp.discord-mcp.svc:8080/mcp`

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml
git commit -m "feat(claude-agents): add discord MCP server to read agent config

Ref #823"
```

---

### Task 6: Add Discord MCP Network Policy to Agent Runners

**Files:**
- Modify: `cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml` (append after last policy)

- [ ] **Step 1: Add the discord-mcp egress policy**

Append to `cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml` after the existing `allow-github-mcp-egress` policy:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to Discord MCP server
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

- [ ] **Step 2: Validate YAML syntax**

```bash
yamllint cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml
```

Expected: no errors (warnings about line length are OK)

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml
git commit -m "feat(claude-agents): add discord-mcp egress network policy

Ref #823"
```

---

### Task 7: Run QA Validation

- [ ] **Step 1: Run qa-validator agent**

Run the `qa-validator` agent against all modified/created files to check linting, schema validation, and standards compliance.

Key files to validate:
- `cluster/apps/n8n-system/n8n/assets/sre-triage-prompt.md`
- `cluster/apps/n8n-system/n8n/assets/sre-triage-workflow.json`
- `cluster/apps/discord-mcp/` (all new files)
- `cluster/apps/claude-agents-read/claude-agents/app/claude-mcp-config.yaml`
- `cluster/apps/claude-agents-read/claude-agents/app/network-policies.yaml`
- `images/discord-mcp/Dockerfile`
- `.github/workflows/release-discord-mcp.yaml`

- [ ] **Step 2: Fix any issues flagged by qa-validator**

- [ ] **Step 3: Re-commit fixes if needed**

```bash
git add <fixed-files>
git commit -m "fix(n8n): address qa-validator findings for SRE triage

Ref #823"
```

---

## Notes for the Implementer

### Image Build Prerequisite

Before deploying discord-mcp to the cluster (Task 4), the wrapper image must be built and pushed:

1. Merge Tasks 1-3 commits to main
2. Run the `Release Discord MCP` workflow manually (dispatch with bump=patch)
3. Verify image at `ghcr.io/anthony-spruyt/discord-mcp:0.1.0`
4. Then deploy Task 4 manifests

### SOPS Secret (Manual Step)

The discord-mcp SOPS secret (`discord-secrets.sops.yaml`) must be created manually by the user. The implementer should skip this file and remind the user to create it before pushing.

### n8n Workflow Template

The workflow JSON is a **starting template**. After import into n8n:
1. Configure Discord bot credentials
2. Configure Valkey (Redis) credentials (reuse existing n8n connection)
3. Configure Claude Code CLI credentials
4. Paste the system prompt from `sre-triage-prompt.md` into the Claude Code CLI node
5. Set the webhook path to match Alertmanager config
6. Test with a manual webhook POST

### Valkey Key Pattern

Keys follow: `sre:thread:<alertname>:<instance>:<startsAt>`

Instance priority from alert labels:
1. `labels.instance`
2. `labels.pod`
3. `labels.deployment`
4. `labels.namespace`
5. Literal `cluster`

TTL: 604800 seconds (7 days) — auto-cleanup, no manual pruning needed.

### Discord API FQDNs

The discord-mcp network policy allows egress to:
- `discord.com` / `*.discord.com` — REST API
- `gateway.discord.gg` / `*.discord.gg` — WebSocket gateway (JDA bot connection)
- `*.discord.media` — Attachment CDN (if needed)

If additional domains are needed at runtime, check pod logs for DNS resolution failures.
