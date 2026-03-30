# Phase 1: n8n Claude Code CLI Node Setup

**Issue:** #823 (Phase 1 only)
**Date:** 2026-03-30
**Status:** Draft

## Summary

Add a Claude Code execution layer to the existing n8n deployment. n8n workflows spawn ephemeral pods in a dedicated `claude-agents` namespace that run `claude -p` with native Claude Code configuration (OAuth credentials, MCP servers, settings). This is the foundation for phase 2's operational workflows (alertmanager triage, GitHub issue triage, etc.).

## Architecture

```text
┌─ n8n (n8n-system) ─────────────────────────────────────────┐
│  Main + Worker + Webhook pods (existing)                    │
│  Community node: n8n-nodes-claude-code-cli (via env var)    │
│  Dedicated SA: n8n-claude-spawner (creates/deletes pods)    │
└─────────────┬───────────────────────────────────────────────┘
              │ K8s API (create/delete/get/logs pods)
              ▼
┌─ claude-agents namespace ───────────────────────────────────┐
│  Ephemeral pods (one per task, auto-deleted after)          │
│  Image: ghcr.io/anthony-spruyt/claude-agent                │
│  SA: claude-agent (reads own secrets/configmaps)            │
│                                                             │
│  Bootstrap (entrypoint.sh):                                 │
│  1. kubectl get secret → ~/.claude/.credentials.json        │
│  2. kubectl get configmap → /workspace/.mcp.json            │
│  3. kubectl get configmap → ~/.claude/settings.json         │
│  4. rm -f $(which kubectl)  # remove before agent starts   │
│  5. exec claude "$@"                                        │
│                                                             │
│  Per-workflow control via CLI flags:                         │
│  --allowedTools, --disallowedTools, --max-turns,            │
│  --max-budget-usd, --channels, system prompt                │
└─────────────┬───────────────────────────────────────────────┘
              │ CNPs (egress)
              ▼
┌─ In-Cluster Services ──────────────────────────────────────┐
│  kubectl-mcp-server.kubectl-mcp.svc:8000 (HTTP MCP)        │
│  mcp-victoriametrics.observability.svc:8080 (HTTP MCP)     │
└─────────────────────────────────────────────────────────────┘
              │
              ▼
┌─ External ──────────────────────────────────────────────────┐
│  api.anthropic.com (Claude API — subscription auth)         │
│  discord.com / gateway.discord.gg (channels)                │
│  World egress (CNP allows all)                              │
└─────────────────────────────────────────────────────────────┘
```

## Components

### 1. Community Node Installation

Install `n8n-nodes-claude-code-cli` via the `N8N_COMMUNITY_PACKAGES` environment variable in n8n's `values.yaml`. This is declarative and GitOps-managed — n8n auto-installs the package on startup.

**Change:** Add to `main.extraEnv`, which propagates to worker and webhook via YAML anchors:

```yaml
N8N_COMMUNITY_PACKAGES:
  value: "n8n-nodes-claude-code-cli"
```

### 2. Container Image (`claude-agent`)

Built in `anthony-spruyt/container-images/claude-agent/` using the existing image factory pipeline.

**Contents:**

| Component         | Purpose                                                              |
| ----------------- | -------------------------------------------------------------------- |
| Node.js           | Claude CLI runtime dependency                                        |
| Python            | Agent tooling                                                        |
| git               | Repository operations                                                |
| npm               | Package management                                                   |
| kubectl           | Bootstrap config fetching only (deleted before agent starts)         |
| Claude CLI        | Native installer (`curl -fsSL https://claude.ai/install.sh \| bash`) |
| Aikido safe-chain | Supply chain security for npm/pip                                    |

**Entrypoint script:**

```bash
#!/bin/bash
set -euo pipefail

# Bootstrap: fetch config from K8s API
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

kubectl get secret claude-credentials -n "$NAMESPACE" \
  -o jsonpath='{.data.credentials\.json}' | base64 -d > ~/.claude/.credentials.json

kubectl get configmap claude-mcp-config -n "$NAMESPACE" \
  -o jsonpath='{.data.mcp\.json}' > /workspace/.mcp.json

kubectl get configmap claude-settings -n "$NAMESPACE" \
  -o jsonpath='{.data.settings\.json}' > ~/.claude/settings.json

# Remove kubectl — agent must use MCP for K8s operations
rm -f "$(which kubectl)"

exec claude "$@"
```

**Filesystem writability:** The entrypoint writes to `~/.claude/` and `/workspace/`,
and deletes kubectl from the filesystem. PSA `restricted` does NOT enforce
`readOnlyRootFilesystem` — it only requires `runAsNonRoot`,
`allowPrivilegeEscalation: false`, `seccompProfile`, and dropping capabilities.
The community node's pod spec builder does not set `readOnlyRootFilesystem`, so
the container filesystem is writable by default. kubectl should be installed to a
user-writable path (e.g., `~/bin/kubectl`) to ensure the `rm` succeeds regardless
of the runtime user.

**What is NOT in the image:** No credentials, MCP config, or settings. All injected at runtime from K8s resources.

**Published to:** `ghcr.io/anthony-spruyt/claude-agent`

### 3. Namespace: `claude-agents`

Standard app namespace following existing patterns.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: claude-agents
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

Descheduler excluded — ephemeral pods are short-lived, eviction wastes work. Per the upstream descheduler bug, dual-exclusion is required: the namespace label above AND adding `claude-agents` to per-plugin `namespaces.exclude` lists in `cluster/apps/kube-system/descheduler/app/values.yaml`.

**VPA exception:** No `vpa.yaml` is included. VPA targets Deployments/StatefulSets — this namespace only has ephemeral pods with no persistent controller. This is a documented exception to the "every workload must include VPA" pattern.

### 4. RBAC

**Two service accounts, two roles — strict separation of concerns.**

#### Spawner (creates pods)

- **ServiceAccount:** `n8n-claude-spawner` in `n8n-system`
- **Role:** `claude-pod-manager` in `claude-agents`
  - `pods`: create, get, list, watch, delete
  - `pods/log`: get
  - `pods/status`: get
  - `pods/exec`: create (may be needed if community node uses exec API for output streaming — verify during implementation)
- **RoleBinding:** `n8n-claude-spawner-binding` in `claude-agents`
  - Binds Role to SA across namespaces

The community node's K8s credential supports three auth methods: in-cluster SA,
kubeconfig file, or inline kubeconfig. Since `n8n-claude-spawner` is a dedicated
SA (not the n8n worker's own SA), the node must authenticate via a **kubeconfig**
referencing the spawner SA's token. Implementation approach: create a long-lived
token Secret for the SA, generate a kubeconfig from it, and store it as an n8n
credential (inline kubeconfig in the n8n UI). This is the one piece of config that
lives in n8n's database rather than Git.

#### Agent (reads its own config)

- **ServiceAccount:** `claude-agent` in `claude-agents`
- **Role:** `claude-config-reader` in `claude-agents`
  - `secrets`: get — restricted via `resourceNames: [claude-credentials]`
  - `configmaps`: get — restricted via `resourceNames: [claude-mcp-config, claude-settings]`
- **RoleBinding:** `claude-agent-binding` in `claude-agents`

Mounted on ephemeral pods. Minimal read-only access to its own config resources only. kubectl is removed from the pod after bootstrap, so even if the agent tries to use it, it can't.

### 5. Network Policies (CiliumNetworkPolicies)

#### In `claude-agents` namespace (new)

**allow-kube-api-egress** — ephemeral pods to K8s API (bootstrap only — kubectl is removed after):

```yaml
endpointSelector:
  matchLabels:
    app.kubernetes.io/name: claude-agent
egress:
  - toEntities:
      - kube-apiserver
    toPorts:
      - ports:
          - port: "6443"
            protocol: TCP
```

**allow-world-egress** — ephemeral pods to external services:

```yaml
endpointSelector:
  matchLabels:
    app.kubernetes.io/name: claude-agent
egress:
  - toEntities:
      - world
```

**allow-kubectl-mcp-egress** — to kubectl MCP server:

```yaml
endpointSelector:
  matchLabels:
    app.kubernetes.io/name: claude-agent
egress:
  - toEndpoints:
      - matchLabels:
          k8s:io.kubernetes.pod.namespace: kubectl-mcp
          k8s:app.kubernetes.io/name: kubectl-mcp-server
    toPorts:
      - ports:
          - port: "8000"
            protocol: TCP
```

**allow-victoriametrics-mcp-egress** — to VictoriaMetrics MCP server:

```yaml
endpointSelector:
  matchLabels:
    app.kubernetes.io/name: claude-agent
egress:
  - toEndpoints:
      - matchLabels:
          k8s:io.kubernetes.pod.namespace: observability
          k8s:app.kubernetes.io/name: mcp-victoriametrics
    toPorts:
      - ports:
          - port: "8080"
            protocol: TCP
```

#### In `kubectl-mcp` namespace (update existing)

Add ingress rule to existing network policies allowing traffic from `claude-agents`:

```yaml
fromEndpoints:
  - matchLabels:
      k8s:io.kubernetes.pod.namespace: claude-agents
      k8s:app.kubernetes.io/name: claude-agent
toPorts:
  - ports:
      - port: "8000"
        protocol: TCP
```

#### In `observability` namespace (update existing)

Add ingress rule on `mcp-victoriametrics` allowing traffic from `claude-agents`:

```yaml
fromEndpoints:
  - matchLabels:
      k8s:io.kubernetes.pod.namespace: claude-agents
      k8s:app.kubernetes.io/name: claude-agent
toPorts:
  - ports:
      - port: "8080"
        protocol: TCP
```

**Note:** DNS egress handled by existing `CiliumClusterwideNetworkPolicy allow-kube-dns-egress`. Ephemeral pod labels (`app.kubernetes.io/name: claude-agent`) must match what the community node applies — verify during implementation.

### 6. Config Resources

#### Secret: `claude-credentials` (SOPS-encrypted)

Contains OAuth `.credentials.json` for Claude subscription auth. Same credential pattern as `openclaw-workspace-config`.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: claude-credentials
  namespace: claude-agents
type: Opaque
stringData:
  credentials.json: |
    { ... }  # OAuth token from claude login
```

#### ConfigMap: `claude-mcp-config`

MCP server definitions using internal cluster DNS. No API keys needed — CNPs handle access control.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-mcp-config
  namespace: claude-agents
data:
  mcp.json: |
    {
      "mcpServers": {
        "victoriametrics": {
          "type": "http",
          "url": "http://mcp-victoriametrics.observability.svc:8080/mcp"
        },
        "kubernetes": {
          "type": "http",
          "url": "http://kubectl-mcp-server.kubectl-mcp.svc:8000/mcp"
        }
      }
    }
```

#### ConfigMap: `claude-settings`

Base Claude Code settings. Per-workflow overrides via CLI flags.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-settings
  namespace: claude-agents
data:
  settings.json: |
    {
      "permissions": {
        "deny": []
      }
    }
```

Exact settings TBD during implementation — will depend on what base restrictions make sense across all workflows.

### 7. n8n Dependency Update

Update `cluster/apps/n8n-system/n8n/ks.yaml` to depend on the `claude-agents` Kustomization:

```yaml
dependsOn:
  - name: authentik
  - name: cnpg-operator
  - name: plugin-barman-cloud
  - name: valkey
  - name: claude-agents  # new
```

The `claude-agents` ks.yaml itself should include `prune: true`, `wait: true`, and `timeout: 5m` following the existing pattern. No `dependsOn` needed — the namespace resources (RBAC, ConfigMaps, CNPs) have no external dependencies beyond the cluster-wide defaults.

### 8. Ephemeral Pod Resources & Timeouts

**Resource limits** (configured in community node's K8s credential):

- CPU limit: `1` (default)
- Memory limit: `2Gi`
- Memory request: `512Mi` (if configurable, otherwise inherits from limit)

**Timeout control:**

- Community node timeout: 300s default, configurable up to 3600s per workflow node
- `--max-turns`: per-workflow, limits agentic loop iterations
- `--max-budget-usd`: per-workflow, cost cap
- Pod `activeDeadlineSeconds`: not set by community node — if a pod hangs past the node timeout, the node deletes it in its `finally` block. If the n8n worker itself crashes mid-execution, orphaned pods remain until manual cleanup or a CronJob sweeper (phase 2 consideration).

### 9. PoC Workflow

Manual trigger in n8n UI to validate end-to-end:

**Claude Code node config:**

- System prompt: "You are a test agent. Confirm you can access MCP servers by listing Kubernetes namespaces and querying a VictoriaMetrics metric. Post your findings to Discord."
- `--max-turns 5`
- `--max-budget-usd 1.00`
- `--channels plugin:discord@claude-plugins-official`

**Success criteria:**

1. Pod spawns in `claude-agents` namespace
2. Entrypoint bootstraps config from K8s API
3. kubectl is removed before agent starts
4. Claude authenticates via OAuth (subscription)
5. MCP servers reachable (kubectl-mcp, victoriametrics)
6. Discord channel receives message via Claude channels
7. Pod auto-deletes after completion
8. n8n workflow shows successful execution with output

## File Structure

```text
cluster/apps/claude-agents/
├── namespace.yaml
├── kustomization.yaml
└── claude-agents/
    ├── ks.yaml
    └── app/
        ├── kustomization.yaml
        ├── claude-credentials.sops.yaml
        ├── claude-mcp-config.yaml        # ConfigMap
        ├── claude-settings.yaml          # ConfigMap
        ├── rbac.yaml                     # SA + Role + RoleBinding (agent)
        ├── rbac-spawner.yaml             # SA + Role + RoleBinding (spawner, in n8n-system)
        └── network-policies.yaml         # CNPs for claude-agents namespace
    └── README.md
```

**Notes:**

- `rbac-spawner.yaml` creates the SA in `n8n-system` and binds it to a Role in `claude-agents`. The SA resource must have an explicit `namespace: n8n-system` metadata field to override the Kustomization's `targetNamespace: claude-agents`.
- The entrypoint script reads a secret via `kubectl get secret -o jsonpath`. This is the entrypoint script in the container image, not Claude itself — the project constraint against `kubectl get secret -o jsonpath` applies to Claude's behavior, not to infrastructure bootstrap scripts.

**Changes to existing files:**

- `cluster/apps/n8n-system/n8n/app/values.yaml` — Add `N8N_COMMUNITY_PACKAGES` env var
- `cluster/apps/n8n-system/n8n/ks.yaml` — Add `dependsOn: claude-agents`
- `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml` — Add ingress from `claude-agents`
- `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` — Add ingress from `claude-agents`
- `cluster/apps/kustomization.yaml` — Add `claude-agents` entry
- `cluster/apps/kube-system/descheduler/app/values.yaml` — Add `claude-agents` to per-plugin `namespaces.exclude` lists

**Separate repo:**

- `anthony-spruyt/container-images` — New `claude-agent/` directory with Dockerfile, entrypoint.sh, metadata.yaml

## Security Considerations

| Concern             | Mitigation                                                                    |
| ------------------- | ----------------------------------------------------------------------------- |
| Credential exposure | OAuth credentials in SOPS-encrypted secret, fetched at bootstrap only         |
| Agent K8s access    | kubectl removed after bootstrap; SA has read-only access to own config only   |
| Agent blast radius  | All K8s operations go through kubectl-mcp (which has its own scoped RBAC)     |
| Network access      | World egress allowed (agents need external APIs), MCP access via CNPs         |
| Supply chain        | Aikido safe-chain in image protects npm/pip installs                          |
| Cost control        | Per-workflow `--max-turns` and `--max-budget-usd` limits                      |
| Pod cleanup         | Community node auto-deletes pods in `finally` block; timeout as fallback      |
| Spawner isolation   | Dedicated SA for pod creation, not shared with n8n worker SA                  |

## Out of Scope (Phase 2+)

- Operational workflows (alertmanager, GitHub triage, HA events, scheduled maintenance)
- OpenClaw decommissioning
- Code agents (Gastown — separate issue #824)
- n8n Discord node integration for simple notifications
- Discord channel plugin configuration/pairing in ephemeral pods

## Open Questions

1. **Ephemeral pod labels:** What labels does the community node apply to spawned pods? CNP selectors depend on this. Verify during implementation — may need to configure via the node's credential settings or fork if not configurable.
2. **Discord channels in ephemeral pods:** The Discord plugin requires a bot token and pairing. How is the bot token injected? Likely via env var (`DISCORD_BOT_TOKEN`) through the community node's `envVars` field, but pairing flow needs investigation for headless/ephemeral context.
3. **Claude CLI version pinning:** The native installer (`claude.ai/install.sh`) installs latest. For reproducibility, we may want to pin a specific version in the Dockerfile. Check if the installer supports version arguments.
4. **Pod security context:** The `restricted` PSA requires `runAsNonRoot`,
   `seccompProfile: RuntimeDefault`, drop all capabilities. The community node's
   pod spec builder does NOT set `securityContext` fields. Options: (a) fork the
   node to add security context support, (b) drop PSA to `baseline` for this
   namespace, (c) use a mutating admission webhook/policy to inject security
   context. Verify during implementation.
5. **OAuth token refresh lifecycle:** The `.credentials.json` contains an OAuth
   token from `claude login`. OAuth tokens expire. Questions to resolve: What is
   the token lifetime? Does Claude Code handle refresh automatically if the
   refresh token is present? If not, who refreshes — manual `claude login` and
   re-encrypt the secret? Could a scheduled n8n workflow handle refresh? This is
   a potential operational burden that needs a clear answer before production use.
