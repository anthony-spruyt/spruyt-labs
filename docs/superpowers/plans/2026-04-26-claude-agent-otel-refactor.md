# Claude Agent OTel + Kyverno/MCP Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenTelemetry telemetry to Claude agent pods while refactoring Kyverno injection, MCP config, and network policies to per-namespace isolation.

**Architecture:** Kyverno ClusterPolicy rewritten with shared + per-namespace rules. MCP configs split into three namespace-specific configmaps. New `claude-agents-sre` namespace with isolated SRE credentials. OTel env vars injected via shared Kyverno rule. Phase 2 adds VictoriaTraces.

**Tech Stack:** Kyverno, CiliumNetworkPolicy, Flux Kustomization, VictoriaMetrics, VictoriaLogs, Grafana, SOPS/Age

**Spec:** `docs/superpowers/specs/2026-04-26-claude-agent-otel-refactor-design.md` **Issue:** [#1043](https://github.com/anthony-spruyt/spruyt-labs/issues/1043)

______________________________________________________________________

## Phase 1: Config Refactor + OTel

### Task 1: Legacy Cleanup — Delete renovate files, strip settings denylists

**Files:**

- Delete: `cluster/apps/claude-agents-shared/base/settings/renovate-triage.json`

- Delete: `cluster/apps/claude-agents-shared/base/settings/renovate-write.json`

- Modify: `cluster/apps/claude-agents-shared/base/settings/dev.json`

- Modify: `cluster/apps/claude-agents-shared/base/settings/pr.json`

- Modify: `cluster/apps/claude-agents-shared/base/settings/sre.json`

- Modify: `cluster/apps/claude-agents-shared/base/kustomization.yaml`

- No change: `cluster/apps/claude-agents-shared/base/settings/admin.json` (already schema-only)

- [ ] **Step 1: Delete legacy renovate settings files**

```bash
rm cluster/apps/claude-agents-shared/base/settings/renovate-triage.json
rm cluster/apps/claude-agents-shared/base/settings/renovate-write.json
```

- [ ] **Step 2: Strip `deniedMcpServers` from dev.json**

Replace contents of `cluster/apps/claude-agents-shared/base/settings/dev.json` with:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json"
}
```

- [ ] **Step 3: Strip `deniedMcpServers` from pr.json**

Replace contents of `cluster/apps/claude-agents-shared/base/settings/pr.json` with:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json"
}
```

- [ ] **Step 4: Strip `deniedMcpServers` from sre.json**

Replace contents of `cluster/apps/claude-agents-shared/base/settings/sre.json` with:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json"
}
```

- [ ] **Step 5: Remove renovate profiles from kustomization.yaml configMapGenerator**

In `cluster/apps/claude-agents-shared/base/kustomization.yaml`, remove these lines from the `configMapGenerator[0].files` list:

```yaml
      - settings/renovate-triage.json
      - settings/renovate-write.json
```

- [ ] **Step 6: Validate kustomize build**

```bash
kubectl kustomize cluster/apps/claude-agents-shared/base/ > /dev/null
```

Expected: exits 0, no errors.

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/settings/dev.json \
       cluster/apps/claude-agents-shared/base/settings/pr.json \
       cluster/apps/claude-agents-shared/base/settings/sre.json \
       cluster/apps/claude-agents-shared/base/kustomization.yaml
git rm cluster/apps/claude-agents-shared/base/settings/renovate-triage.json \
       cluster/apps/claude-agents-shared/base/settings/renovate-write.json
git commit -m "chore(agents): remove legacy renovate settings and MCP denylists

Strip deniedMcpServers from dev/pr/sre profiles — access now
controlled by per-namespace MCP configmaps (next commit).
Delete renovate-triage.json and renovate-write.json (legacy).

Ref #1043"
```

______________________________________________________________________

### Task 2: Per-Namespace MCP ConfigMaps

**Files:**

- Delete: `cluster/apps/claude-agents-shared/base/claude-mcp-config.yaml`

- Create: `cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml`

- Create: `cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml`

- Create: `cluster/apps/claude-agents-shared/base/claude-mcp-config-sre.yaml`

- Modify: `cluster/apps/claude-agents-shared/base/kustomization.yaml`

- [ ] **Step 1: Create read MCP configmap**

Create `cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/configmap-v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-mcp-config-read
data:
  mcp.json: |
    {
      "mcpServers": {
        "bravesearch": {
          "type": "http",
          "url": "http://brave-search-mcp.brave-search-mcp.svc:8000/mcp"
        },
        "context7": {
          "type": "http",
          "url": "https://mcp.context7.com/mcp",
          "headers": {
            "CONTEXT7_API_KEY": "$${CONTEXT7_API_KEY}"
          }
        },
        "github": {
          "type": "http",
          "url": "http://github-mcp-server.github-mcp.svc:8082/mcp"
        }
      }
    }
```

- [ ] **Step 2: Create write MCP configmap**

Create `cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/configmap-v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-mcp-config-write
data:
  mcp.json: |
    {
      "mcpServers": {
        "bravesearch": {
          "type": "http",
          "url": "http://brave-search-mcp.brave-search-mcp.svc:8000/mcp"
        },
        "context7": {
          "type": "http",
          "url": "https://mcp.context7.com/mcp",
          "headers": {
            "CONTEXT7_API_KEY": "$${CONTEXT7_API_KEY}"
          }
        },
        "discord": {
          "type": "http",
          "url": "http://discord-mcp.discord-mcp.svc:8080/mcp"
        },
        "github": {
          "type": "http",
          "url": "http://github-mcp-server.github-mcp.svc:8082/mcp"
        },
        "kubectl": {
          "type": "http",
          "url": "http://kubectl-mcp-server.kubectl-mcp.svc:8000/mcp"
        },
        "victoriametrics": {
          "type": "http",
          "url": "http://mcp-victoriametrics.observability.svc:8080/mcp"
        }
      }
    }
```

- [ ] **Step 3: Create SRE MCP configmap**

Create `cluster/apps/claude-agents-shared/base/claude-mcp-config-sre.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/configmap-v1.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-mcp-config-sre
data:
  mcp.json: |
    {
      "mcpServers": {
        "bravesearch": {
          "type": "http",
          "url": "http://brave-search-mcp.brave-search-mcp.svc:8000/mcp"
        },
        "context7": {
          "type": "http",
          "url": "https://mcp.context7.com/mcp",
          "headers": {
            "CONTEXT7_API_KEY": "$${CONTEXT7_API_KEY}"
          }
        },
        "discord": {
          "type": "http",
          "url": "http://discord-mcp.discord-mcp.svc:8080/mcp"
        },
        "github": {
          "type": "http",
          "url": "http://github-mcp-server.github-mcp.svc:8082/mcp"
        },
        "kubectl": {
          "type": "http",
          "url": "http://kubectl-mcp-server.kubectl-mcp.svc:8000/mcp"
        },
        "sre": {
          "type": "http",
          "url": "http://n8n-webhook.n8n-system.svc/mcp/sre",
          "headers": {
            "Authorization": "Bearer $${SRE_MCP_AUTH_TOKEN}"
          }
        },
        "victoriametrics": {
          "type": "http",
          "url": "http://mcp-victoriametrics.observability.svc:8080/mcp"
        }
      }
    }
```

- [ ] **Step 4: Update shared base kustomization.yaml**

In `cluster/apps/claude-agents-shared/base/kustomization.yaml`, replace ONLY the `resources:` list — keep `configMapGenerator` and `generatorOptions` sections intact (Task 1 already pruned renovate entries from `configMapGenerator`). Final file should be exactly:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./rbac.yaml
  - ./rbac-spawner.yaml
  - ./network-policies.yaml
  - ./github-secret-store.yaml
  - ./github-ssh-external-secret.yaml
  - ./github-bot-gitconfig.yaml
  - ./github-rotation-rbac.yaml
  - ./claude-mcp-config-read.yaml
  - ./claude-mcp-config-write.yaml
  - ./claude-mcp-config-sre.yaml
  - ./mcp-credentials.sops.yaml
configMapGenerator:
  - name: claude-settings-profiles
    files:
      - settings/admin.json
      - settings/dev.json
      - settings/pr.json
      - settings/sre.json
generatorOptions:
  disableNameSuffixHash: true
```

- [ ] **Step 5: Delete old configmap**

```bash
rm cluster/apps/claude-agents-shared/base/claude-mcp-config.yaml
```

- [ ] **Step 6: Validate kustomize build**

```bash
kubectl kustomize cluster/apps/claude-agents-shared/base/ > /dev/null
```

Expected: exits 0, no errors.

- [ ] **Step 7: Commit**

```bash
git rm cluster/apps/claude-agents-shared/base/claude-mcp-config.yaml
git add cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml \
       cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml \
       cluster/apps/claude-agents-shared/base/claude-mcp-config-sre.yaml \
       cluster/apps/claude-agents-shared/base/kustomization.yaml
git commit -m "feat(agents): split MCP config into per-namespace configmaps

Replace single claude-mcp-config with three namespace-specific
configmaps (read/write/sre). Each namespace gets only the MCP
servers it needs — allowlist replaces denylist pattern.

Removed: renovate, homeassistant MCP entries.

Ref #1043"
```

______________________________________________________________________

### Task 3: New `claude-agents-sre` Namespace

**Files:**

- Create: `cluster/apps/claude-agents-sre/namespace.yaml`

- Create: `cluster/apps/claude-agents-sre/kustomization.yaml`

- Create: `cluster/apps/claude-agents-sre/claude-agents/ks.yaml`

- Create: `cluster/apps/claude-agents-sre/claude-agents/README.md`

- Create: `cluster/apps/claude-agents-sre/claude-agents/app/kustomization.yaml`

- Create: `cluster/apps/claude-agents-sre/claude-agents/app/github-external-secret.yaml`

- Create: `cluster/apps/claude-agents-sre/claude-agents/app/network-policies.yaml`

- Reference: `cluster/apps/claude-agents-read/namespace.yaml` (pattern)

- Reference: `cluster/apps/claude-agents-read/claude-agents/app/github-external-secret.yaml` (pattern)

- [ ] **Step 1: Create namespace.yaml**

Create `cluster/apps/claude-agents-sre/namespace.yaml`:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: claude-agents-sre
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 2: Create top-level kustomization.yaml**

Create `cluster/apps/claude-agents-sre/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./claude-agents/ks.yaml
```

- [ ] **Step 3: Create Flux Kustomization (ks.yaml)**

Create `cluster/apps/claude-agents-sre/claude-agents/ks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app claude-agents-sre
  namespace: flux-system
spec:
  targetNamespace: claude-agents-sre
  path: ./cluster/apps/claude-agents-sre/claude-agents/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: github-token-rotation
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 4: Create app kustomization.yaml**

Create `cluster/apps/claude-agents-sre/claude-agents/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../claude-agents-shared/base
  - ./github-external-secret.yaml
  - ./network-policies.yaml
  - ./sre-credentials.sops.yaml
```

Note: `sre-credentials.sops.yaml` is created manually by user in Task 9. Resource entry MUST be present — without it, kustomize won't include the secret and Kyverno `inject-sre-mcp` rule will fail to inject `SRE_MCP_AUTH_TOKEN`.

- [ ] **Step 5: Create github-external-secret.yaml (read-tier — SRE doesn't commit)**

Create `cluster/apps/claude-agents-sre/claude-agents/app/github-external-secret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
# Syncs read-tier GitHub OAuth credentials from github-system
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: github-bot-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: SecretStore
    name: github-secret-store
  target:
    name: github-bot-credentials
    creationPolicy: Owner
  data:
    - secretKey: hosts.yml
      remoteRef:
        key: github-bot-credentials
        property: read-hosts.yml
    - secretKey: access-token
      remoteRef:
        key: github-bot-credentials
        property: read-access-token
```

- [ ] **Step 6: Create SRE-specific network policies**

Create `cluster/apps/claude-agents-sre/claude-agents/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kubectl MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kubectl-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kubectl-mcp
            k8s:app.kubernetes.io/name: kubectl-mcp-server
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VictoriaMetrics MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-victoriametrics-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
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
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to n8n SRE MCP endpoint
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-n8n-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: n8n-system
            k8s:app.kubernetes.io/name: n8n
            k8s:app.kubernetes.io/type: webhook
      toPorts:
        - ports:
            - port: "5678"
              protocol: TCP
```

- [ ] **Step 7: Create README.md**

Create `cluster/apps/claude-agents-sre/claude-agents/README.md` using the template from `docs/templates/readme_template.md`:

````markdown
# Claude Agents SRE - SRE Agent Execution Namespace

## Overview

Isolated namespace for Claude Code SRE agent pods spawned by n8n. SRE agents triage incidents and
investigate cluster state but do not commit changes. Uses read-tier GitHub OAuth and high-priority
scheduling to ensure availability during incidents.

> **Note**: Agent pods are created dynamically by n8n workflows, not by Flux HelmReleases.

## Prerequisites

- Kubernetes cluster with Flux CD
- github-token-rotation (provides GitHub bot credentials via ExternalSecret)

## Operation

### Key Commands

```bash
# Check running agent pods
kubectl get pods -n claude-agents-sre

# Check Flux kustomization status
flux get kustomization claude-agents-sre

# Force reconcile (GitOps approach)
flux reconcile kustomization claude-agents-sre --with-source

# View agent pod logs
kubectl logs -n claude-agents-sre -l managed-by=n8n-claude-code
````

## Troubleshooting

### Common Issues

1. **Agent pod stuck in Pending**

   - **Symptom**: Pod remains in Pending state
   - **Resolution**: Check node resources and priority class — SRE pods use `high-priority` (100000)

1. **MCP server connection failures**

   - **Symptom**: Agent cannot reach MCP servers
   - **Resolution**: Verify CiliumNetworkPolicies allow egress to target MCP namespace/port

## References

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)

```text
(end of README)
```

- [ ] **Step 8: Validate kustomize builds**

```bash
kubectl kustomize cluster/apps/claude-agents-sre/claude-agents/app/ > /dev/null
kubectl kustomize cluster/apps/claude-agents-sre/ > /dev/null
```

Expected: both exit 0.

- [ ] **Step 9: Commit**

```bash
git add cluster/apps/claude-agents-sre/
git commit -m "feat(agents): add claude-agents-sre namespace

New namespace for SRE agent pods with read-tier GitHub OAuth,
high-priority scheduling, and isolated SRE MCP access. Includes
network policies for kubectl, victoriametrics, discord, and n8n
SRE MCP egress.

Ref #1043"
```

______________________________________________________________________

### Task 4: Write-Namespace Network Policies

**Files:**

- Create: `cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml`

- Modify: `cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml`

- [ ] **Step 1: Create write-specific network policies**

Create `cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kubectl MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kubectl-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kubectl-mcp
            k8s:app.kubernetes.io/name: kubectl-mcp-server
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VictoriaMetrics MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-victoriametrics-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
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

- [ ] **Step 2: Add network-policies.yaml to write app kustomization**

In `cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml`, add the network policies resource:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../claude-agents-shared/base
  - ./github-external-secret.yaml
  - ./network-policies.yaml
```

- [ ] **Step 3: Validate kustomize build**

```bash
kubectl kustomize cluster/apps/claude-agents-write/claude-agents/app/ > /dev/null
```

Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml \
       cluster/apps/claude-agents-write/claude-agents/app/kustomization.yaml
git commit -m "feat(agents): add write-namespace-specific network policies

Move kubectl, victoriametrics, and discord MCP egress from shared
base to write-namespace-only network policies.

Ref #1043"
```

______________________________________________________________________

### Task 5: Refactor Shared Base Network Policies

**Files:**

- Modify: `cluster/apps/claude-agents-shared/base/network-policies.yaml`

- [ ] **Step 1: Rewrite shared network policies**

Replace contents of `cluster/apps/claude-agents-shared/base/network-policies.yaml` with:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kube-apiserver
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow all egress to world -- agents need external APIs, npm, git, etc.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-world-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEntities:
        - world
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VMSingle for OTLP metrics
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-vmsingle-otlp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmsingle
      toPorts:
        - ports:
            - port: "8428"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VictoriaLogs for OTLP logs/events
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-vlogs-otlp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: victoria-logs-single
      toPorts:
        - ports:
            - port: "9428"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to GitHub MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: github-mcp
            k8s:app.kubernetes.io/name: github-mcp-server
      toPorts:
        - ports:
            - port: "8082"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to Brave Search MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-brave-search-mcp-egress
spec:
  endpointSelector:
    matchLabels:
      managed-by: n8n-claude-code
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: brave-search-mcp
            k8s:app.kubernetes.io/name: brave-search-mcp
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

- [ ] **Step 2: Validate kustomize builds for all namespaces**

```bash
kubectl kustomize cluster/apps/claude-agents-read/claude-agents/app/ > /dev/null
kubectl kustomize cluster/apps/claude-agents-write/claude-agents/app/ > /dev/null
kubectl kustomize cluster/apps/claude-agents-sre/claude-agents/app/ > /dev/null
```

Expected: all exit 0.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/network-policies.yaml
git commit -m "refactor(agents): move per-namespace egress out of shared base

Shared base now only has universal egress: kube-api, world, github-mcp,
brave-search-mcp, vmsingle-otlp (new), vlogs-otlp (new).

kubectl, victoriametrics, discord, n8n MCP egress moved to
per-namespace network policy files.

Ref #1043"
```

______________________________________________________________________

### Task 6: MCP Server Ingress Policies — Add SRE Namespace

**Files:**

- Modify: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`

- Modify: `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`

- Modify: `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml`

- Modify: `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml`

- Modify: `cluster/apps/n8n-system/n8n/app/network-policies.yaml`

- Modify: `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`

- [ ] **Step 1: kubectl-mcp — add sre namespace to fromEndpoints**

In `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`, find the `allow-claude-agents-ingress` policy's `fromEndpoints` list and add a third entry:

```yaml
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-sre
            k8s:managed-by: n8n-claude-code
```

Add it after the existing `claude-agents-read` entry.

- [ ] **Step 2: discord-mcp — add sre namespace ingress rule**

In `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`, add a new CiliumNetworkPolicy after the existing `allow-claude-agents-write-ingress`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agent SRE pods
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-sre-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: discord-mcp
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-sre
            k8s:managed-by: n8n-claude-code
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

- [ ] **Step 3: brave-search-mcp — add sre namespace**

Read `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml` first to check the pattern (consolidated or separate rules), then add sre namespace ingress matching the existing pattern.

- [ ] **Step 4: github-mcp — add sre namespace**

Read `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml` first to check the pattern, then add sre namespace ingress matching the existing pattern.

- [ ] **Step 5: n8n — add sre namespace to claude agent ingress**

In `cluster/apps/n8n-system/n8n/app/network-policies.yaml`, find the `allow-claude-agent-ingress` policy's `fromEndpoints` list and add:

```yaml
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-sre
            managed-by: n8n-claude-code
```

Note: n8n uses `managed-by` without the `k8s:` prefix — match existing pattern exactly.

- [ ] **Step 6: victoriametrics-mcp — add sre namespace**

In `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`, find the `allow-claude-agents-ingress` policy's `fromEndpoints` list and add:

```yaml
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents-sre
            k8s:managed-by: n8n-claude-code
```

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml \
       cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml \
       cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml \
       cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml \
       cluster/apps/n8n-system/n8n/app/network-policies.yaml \
       cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml
git commit -m "feat(agents): add claude-agents-sre ingress to MCP servers

Allow SRE agent pods to reach kubectl, discord, brave-search,
github, n8n, and victoriametrics MCP servers.

Ref #1043"
```

______________________________________________________________________

### Task 6.5: Enable VMSingle OTel Prometheus Naming

**Why:** Claude Code emits OTel metrics with dot notation (`claude_code.cost.usage`). Without conversion, PromQL queries in the dashboard (Task 8) cannot reference dotted names without escaping. Enabling `opentelemetry.usePrometheusNaming` on VMSingle converts dots to underscores at ingestion time, matching the dashboard query format (`claude_code_cost_usage`).

**Must deploy before Task 7** — Kyverno rewrite enables OTel emission. If flag missing when first agent runs, metrics ingest with dotted names and dashboard returns no data.

**Files:**

- Modify: `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml`

- [ ] **Step 1: Add flag to VMSingle extraArgs**

In `cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml`, find the `vmsingle.spec.extraArgs` block and add the OTel flag:

```yaml
vmsingle:
  spec:
    extraArgs:
      search.maxMemoryPerQuery: 1GB
      opentelemetry.usePrometheusNaming: "true"
```

Note: keep existing `search.maxMemoryPerQuery: 1GB` entry. Add new key only.

- [ ] **Step 2: Validate kustomize build**

```bash
kubectl kustomize cluster/apps/observability/victoria-metrics-k8s-stack/app/ > /dev/null
```

Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/observability/victoria-metrics-k8s-stack/app/values.yaml
git commit -m "feat(observability): enable OTel Prometheus naming on VMSingle

Convert OTel metric names with dot notation (claude_code.cost.usage)
to Prometheus underscore format (claude_code_cost_usage) at ingestion.
Required before Claude agents start emitting OTel metrics.

Ref #1043"
```

______________________________________________________________________

### Task 7: Rewrite Kyverno ClusterPolicy

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`

This is the largest task. The complete policy rewrite with 8 rules.

- [ ] **Step 1: Rewrite the ClusterPolicy**

Replace the entire contents of `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml` with the new policy. The policy must contain these rules:

1. **`inject-shared-config`** — matches all 3 namespaces, injects: git volumes/mounts, `CONTEXT7_API_KEY`, `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `MCP_TIMEOUT`, all OTel env vars, settings profiles volume/mount
1. **`inject-read-mcp`** — read namespace only, mounts `claude-mcp-config-read`
1. **`inject-write-mcp`** — write namespace only, mounts `claude-mcp-config-write`
1. **`inject-sre-mcp`** — sre namespace only, mounts `claude-mcp-config-sre`, injects `SRE_MCP_AUTH_TOKEN` from `sre-credentials` secret, sets `priorityClassName: high-priority`
1. **`inject-read-priority`** — read namespace only, sets `priorityClassName: low-priority`
1. **`inject-write-priority`** — write namespace only, sets `priorityClassName: standard` (explicit even though `standard` is `globalDefault: true` — explicit assignment prevents drift if cluster default ever changes and makes intent visible at the pod spec level)
1. **`inject-repo-clone-write`** — write namespace only, clone init container with `pre-commit install`
1. **`inject-repo-clone-read-sre`** — read + sre namespaces, clone init container without pre-commit

Key details for the implementer:

- All rules match label `managed-by: n8n-claude-code`

- Use `patchStrategicMerge` for all mutate rules

- Container selector pattern: `(name): "?*"`

- Clone rules have preconditions checking `CLONE_URL` env var exists and starts with `git@github.com:anthony-spruyt/`

- OTel env vars from spec section "OTel Environment Variables (Phase 1)"

- `OTEL_RESOURCE_ATTRIBUTES` uses Kyverno variable: `agent.namespace={{request.object.metadata.namespace}}`

- Removed env vars: `HA_API_KEY`, `RENOVATE_MCP_AUTH_TOKEN`

- `CONTEXT7_API_KEY` sourced from `mcp-credentials` secret (shared, still has this key)

- `SRE_MCP_AUTH_TOKEN` sourced from `sre-credentials` secret (sre namespace only)

- MCP config volume mount path stays `/etc/mcp` — configmap name changes per namespace

- [ ] **Step 2: Validate YAML syntax**

```bash
yamllint cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
```

Expected: no errors (warnings about line length OK).

- [ ] **Step 3: Dry-run kustomize build**

```bash
kubectl kustomize cluster/apps/kyverno/policies/app/ > /dev/null
```

Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "feat(kyverno): rewrite agent injection with shared + per-namespace rules

Shared rule injects: git creds, OTel telemetry, CONTEXT7_API_KEY,
settings profiles to all agent namespaces.

Per-namespace rules inject: namespace-specific MCP configmap,
priority class (read=low, write=standard, sre=high), and
SRE_MCP_AUTH_TOKEN only to sre namespace.

Clone rules: write gets pre-commit, read+sre do not.

Ref #1043"
```

______________________________________________________________________

### Task 8: Grafana Dashboard

**Files:**

- Create: `cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/claude-agents.json`

- [ ] **Step 1: Create dashboard JSON**

Create `cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/claude-agents.json` with a Grafana dashboard containing:

- Template variable: `namespace` — query `label_values(claude_code_session_count, agent_namespace)` with "All" option
- Template variable: standard time range
- Datasource: VictoriaMetrics (use `-- Mixed --` or default prometheus datasource)

Panels (use existing dashboards like `n8n.json` for Grafana JSON structure reference):

1. **Total Cost** — stat panel, datasource: VictoriaMetrics, query: `sum(increase(claude_code_cost_usage{agent_namespace=~"$namespace"}[$__range]))`
1. **Cost Over Time** — timeseries, datasource: VictoriaMetrics, query: `sum(rate(claude_code_cost_usage{agent_namespace=~"$namespace"}[5m])) by (agent_namespace)`
1. **Token Usage by Type** — stacked bar, datasource: VictoriaMetrics, query: `sum(increase(claude_code_token_usage{agent_namespace=~"$namespace"}[$__range])) by (type)`
1. **Cache Hit Rate** — gauge, datasource: VictoriaMetrics, query: `sum(increase(claude_code_token_usage{type="cacheRead",agent_namespace=~"$namespace"}[$__range])) / (sum(increase(claude_code_token_usage{type="input",agent_namespace=~"$namespace"}[$__range])) + sum(increase(claude_code_token_usage{type="cacheRead",agent_namespace=~"$namespace"}[$__range])))`
1. **Active Sessions** — stat, datasource: VictoriaMetrics, query: `sum(increase(claude_code_session_count{agent_namespace=~"$namespace"}[$__range])) by (agent_namespace)`
1. **Lines of Code** — timeseries, datasource: VictoriaMetrics, query: `sum(rate(claude_code_lines_of_code_count{agent_namespace=~"$namespace"}[5m])) by (type)`
1. **Tool Failures** — table, datasource: VictoriaLogs, query: `event.name:"claude_code.tool_result" AND success:false AND agent_namespace:$namespace` — show columns: `_time`, `agent_namespace`, `tool_name`, `error`
1. **Tool Duration (p50/p95)** — timeseries, datasource: VictoriaLogs, two series using stats over `event.name:"claude_code.tool_result" AND agent_namespace:$namespace` — p50 and p95 of `duration_ms`
1. **API Errors** — table, datasource: VictoriaLogs, query: `event.name:"claude_code.api_error" AND agent_namespace:$namespace` — show columns: `_time`, `agent_namespace`, `error`, `model`

Note: Tool failures, Tool duration, and API errors panels require the VictoriaLogs datasource plugin. Metric names use underscores (dots converted by VMSingle's `opentelemetry.usePrometheusNaming` flag enabled in Task 6.5). VictoriaLogs event/field names may need adjustment after first agent run — verify exact field structure in vlogs UI before finalizing queries.

- [ ] **Step 2: Validate JSON syntax**

```bash
python3 -c "import json; json.load(open('cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/claude-agents.json'))"
```

Expected: exits 0 (valid JSON).

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/claude-agents.json
git commit -m "feat(observability): add Claude agents Grafana dashboard

Dashboard for agent cost, token usage, cache hit rate, session
count, and lines of code from VMSingle metrics. Tool failures,
tool duration p50/p95, and API errors panels from VictoriaLogs
events. Namespace variable for filtering by read/write/sre.

Ref #1043"
```

______________________________________________________________________

### Task 9: User Actions Checklist (SOPS + n8n)

These steps require manual user action — the implementer cannot do them.

- [ ] **Step 1: Remind user to edit `mcp-credentials.sops.yaml`**

User must edit `cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml`:

```bash
sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml
```

Remove keys: `ha-api-key`, `renovate-mcp-auth-token`. Keep: `context7-api-key`.

- [ ] **Step 2: Remind user to create `sre-credentials.sops.yaml`**

User must create `cluster/apps/claude-agents-sre/claude-agents/app/sre-credentials.sops.yaml` with:

- Secret name: `sre-credentials`

- Key: `sre-mcp-auth-token`

- Value: the SRE MCP auth token from current `mcp-credentials`

- [ ] **Step 3: Remind user to update n8n workflow**

User manually updates n8n SRE agent workflow to spawn pods in `claude-agents-sre` namespace instead of current namespace.

______________________________________________________________________

### Task 10: Run qa-validator

- [ ] **Step 1: Run qa-validator before final commit**

Run the qa-validator agent to validate all changes before push.

- [ ] **Step 2: Fix any issues found**

Address any linting, schema, or documentation issues.

______________________________________________________________________

## Phase 2: VictoriaTraces (separate PR after Phase 1 is deployed and verified)

### Task 11: VictoriaTraces Deployment

**Files:**

- Create: `cluster/flux/meta/repositories/oci/victoria-traces-single-ocirepo.yaml`
- Create: `cluster/apps/observability/victoria-traces/ks.yaml`
- Create: `cluster/apps/observability/victoria-traces/README.md`
- Create: `cluster/apps/observability/victoria-traces/app/kustomization.yaml`
- Create: `cluster/apps/observability/victoria-traces/app/kustomizeconfig.yaml`
- Create: `cluster/apps/observability/victoria-traces/app/release.yaml`
- Create: `cluster/apps/observability/victoria-traces/app/values.yaml`
- Create: `cluster/apps/observability/victoria-traces/app/vpa.yaml`
- Create: `cluster/apps/observability/victoria-traces/app/network-policies.yaml`
- Modify: `cluster/apps/observability/kustomization.yaml`

Follow existing patterns from `cluster/apps/observability/victoria-logs-single/` for structure. Key values:

- Chart: `victoria-traces-single`
- OCI URL: `oci://ghcr.io/victoriametrics/helm-charts/victoria-traces-single`
- Chart version: `0.0.7` (check latest at implementation time)
- Port: 10428
- Storage: `rbd-fast-delete`, size TBD based on trace volume

### Task 12: Add Traces to Kyverno + Network Policies

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`
- Modify: `cluster/apps/claude-agents-shared/base/network-policies.yaml`

Add to `inject-shared-config` rule env vars:

```yaml
- name: OTEL_TRACES_EXPORTER
  value: otlp
- name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  value: http://victoria-traces-single.observability.svc:10428/insert/opentelemetry/v1/traces
```

Add VictoriaTraces egress to shared network policies (port 10428).

### Task 13: Grafana Traces Datasource + Dashboard Update

Add Tempo-compatible datasource for VictoriaTraces. Add trace panel to claude-agents dashboard linking log events to trace spans.
