# Agent Orchestration Platform — Phase 1A: Cluster Infrastructure & Cleanup

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy all cluster infrastructure for the agent orchestration platform: namespace, Valkey, secrets, CNPs, Kyverno policies, settings profiles, MCP config, alerts, descheduler exclusions, and VPA.

**Architecture:** GitOps-first. All changes are Flux-reconciled YAML manifests in `cluster/`. Two-commit ordering for Kyverno→SOPS dependency. Settings profile cleanup removes dead artifacts, creates new role-based profiles. Dedicated agent Valkey instance with AOF persistence isolated from shared Valkey.

**Tech Stack:** Flux, Kustomize, Helm (Valkey chart, app-template), Cilium CNP, Kyverno, SOPS/Age, ExternalSecrets, VPA, VMRule

**Spec reference:** `docs/superpowers/specs/2026-04-22-agent-orchestration-platform-design.md`

______________________________________________________________________

## Tasks

### Task 1: Settings Profile Cleanup — Remove Dead Profiles

Remove dead settings profiles that have zero active consumers. Note: `renovate-triage.json` and `renovate-write.json` have already been removed from the codebase -- only three stubs remain.

**Files:**

- Delete: `cluster/apps/claude-agents-shared/base/settings/admin.json`

- Delete: `cluster/apps/claude-agents-shared/base/settings/dev.json`

- Delete: `cluster/apps/claude-agents-shared/base/settings/pr.json`

- Modify: `cluster/apps/claude-agents-shared/base/kustomization.yaml`

- [ ] **Step 1: Delete dead profile files**

```bash
git rm cluster/apps/claude-agents-shared/base/settings/admin.json
git rm cluster/apps/claude-agents-shared/base/settings/dev.json
git rm cluster/apps/claude-agents-shared/base/settings/pr.json
```

- [ ] **Step 2: Remove dead profiles from configMapGenerator**

In `cluster/apps/claude-agents-shared/base/kustomization.yaml`, remove these lines from the `configMapGenerator[0].files` list:

```yaml
# REMOVE these lines:
      - settings/admin.json
      - settings/dev.json
      - settings/pr.json
```

After removal, the `files` list should contain only:

```yaml
      - settings/sre.json
```

- [ ] **Step 3: Verify only sre.json remains**

```bash
ls cluster/apps/claude-agents-shared/base/settings/
```

Expected: only `sre.json`

- [ ] **Step 4: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/claude-agents-shared/base/ > /dev/null
```

Expected: exits 0, no errors

______________________________________________________________________

### Task 2: Create New Platform Settings Profiles

Create four role-based settings profiles for the platform.

**Files:**

- Create: `cluster/apps/claude-agents-shared/base/settings/triage.json`

- Create: `cluster/apps/claude-agents-shared/base/settings/fix.json`

- Create: `cluster/apps/claude-agents-shared/base/settings/validate.json`

- Create: `cluster/apps/claude-agents-shared/base/settings/execute.json`

- Modify: `cluster/apps/claude-agents-shared/base/kustomization.yaml`

MCP configs are now per-namespace. Each profile only needs to deny servers that ARE in its namespace's config but should not be available for that role:

- **Read namespace** has: bravesearch, context7, github (+ agent-platform after Task 6)

- **Write namespace** has: bravesearch, context7, discord, github, kubectl, victoriametrics (+ agent-platform after Task 6)

- **SRE namespace** has: bravesearch, context7, discord, github, kubectl, sre, victoriametrics

- [ ] **Step 1: Create triage.json**

Triage runs in read namespace. All read-namespace servers are needed -- deny nothing.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": []
}
```

Write to `cluster/apps/claude-agents-shared/base/settings/triage.json`.

- [ ] **Step 2: Create fix.json**

Fix runs in write namespace. Discord and victoriametrics are not needed for code-fix agents.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": [
    { "serverName": "discord" },
    { "serverName": "victoriametrics" }
  ]
}
```

Write to `cluster/apps/claude-agents-shared/base/settings/fix.json`.

- [ ] **Step 3: Create validate.json**

Validate runs in read namespace. All read-namespace servers are needed. **Known gap:** validate agents need kubectl + victoriametrics access for cluster validation, but the read namespace MCP config does not include these servers. This requires either: (a) running validate in the write namespace, or (b) adding kubectl + victoriametrics to `claude-mcp-config-read.yaml`. This is a separate task --
for now the profile denies nothing since read namespace has no servers that need restricting.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": []
}
```

Write to `cluster/apps/claude-agents-shared/base/settings/validate.json`.

- [ ] **Step 4: Create execute.json**

Execute runs in write namespace. Discord, kubectl, and victoriametrics are not needed for code execution agents.

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": [
    { "serverName": "discord" },
    { "serverName": "kubectl" },
    { "serverName": "victoriametrics" }
  ]
}
```

Write to `cluster/apps/claude-agents-shared/base/settings/execute.json`.

- [ ] **Step 5: Add new profiles to configMapGenerator**

In `cluster/apps/claude-agents-shared/base/kustomization.yaml`, add to `configMapGenerator[0].files`:

```yaml
configMapGenerator:
  - name: claude-settings-profiles
    files:
      - settings/sre.json
      - settings/triage.json
      - settings/fix.json
      - settings/validate.json
      - settings/execute.json
```

**Important:** Preserve the existing `generatorOptions` block in the kustomization:

```yaml
generatorOptions:
  disableNameSuffixHash: true
```

This prevents hash suffix changes that would break Kyverno volume mount references to `claude-settings-profiles`.

- [ ] **Step 6: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/claude-agents-shared/base/ > /dev/null
```

Expected: exits 0

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/settings/triage.json \
       cluster/apps/claude-agents-shared/base/settings/fix.json \
       cluster/apps/claude-agents-shared/base/settings/validate.json \
       cluster/apps/claude-agents-shared/base/settings/execute.json \
       cluster/apps/claude-agents-shared/base/kustomization.yaml
git commit -m "feat(agents): replace dead settings profiles with platform role profiles

Remove admin.json, dev.json, pr.json (zero active consumers). Create
triage.json, fix.json, validate.json, execute.json for agent orchestration
platform roles with per-namespace deny lists.

Ref #<issue>"
```

Note: Tasks 1 and 2 are combined into a single commit since removing and creating profiles is one logical change.

______________________________________________________________________

### Task 3: Update sre.json — Add agent-platform Deny

`sre.json` is currently an empty stub (just `$schema`). No `renovate` deny exists to remove -- that was already cleaned up. The only change is adding the `agent-platform` deny.

**Files:**

- Modify: `cluster/apps/claude-agents-shared/base/settings/sre.json`

- [ ] **Step 1: Read current sre.json**

Verify it is an empty stub with only `$schema`.

- [ ] **Step 2: Add `deniedMcpServers` with `agent-platform` deny**

SRE agents don't use platform handoff tools. Update `sre.json` to:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "deniedMcpServers": [
    { "serverName": "agent-platform" }
  ]
}
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/settings/sre.json
git commit -m "chore(agents): add agent-platform deny to sre.json

SRE agents don't use platform handoff. Add agent-platform to
deniedMcpServers.

Ref #<issue>"
```

______________________________________________________________________

### Task 4: ~~Remove Dead Renovate MCP Server Entry~~ ✅ DONE

**Status:** Already completed. The monolithic `claude-mcp-config.yaml` no longer exists -- it was split into three per-namespace ConfigMaps:

- `cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml` (bravesearch, context7, github)
- `cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml` (bravesearch, context7, discord, github, kubectl, victoriametrics)
- `cluster/apps/claude-agents-shared/base/claude-mcp-config-sre.yaml` (bravesearch, context7, discord, github, kubectl, sre, victoriametrics)

None of these configs contain a `renovate` MCP server entry. No action required.

______________________________________________________________________

### Task 5: ~~Remove RENOVATE_MCP_AUTH_TOKEN from Kyverno~~ ✅ Kyverno Side DONE

**Status:** The Kyverno policy has been completely restructured. The old `inject-write-config` and `inject-read-config` rules no longer exist. The current Kyverno policy (`inject-claude-agent-config.yaml`) has 9 rules:

- `inject-shared-config` (read, write, sre) -- shared volumes, env vars, OTel
- `inject-read-mcp` (read) -- mounts claude-mcp-config-read
- `inject-write-mcp` (write) -- mounts claude-mcp-config-write + SSH + gitconfig
- `inject-sre-mcp` (sre) -- mounts claude-mcp-config-sre + SRE_MCP_AUTH_TOKEN + high-priority
- `strip-explicit-priority` (all) -- removes explicit spec.priority
- `inject-read-priority` (read) -- sets low-priority
- `inject-write-priority` (write) -- sets standard
- `inject-repo-clone-write` (write) -- SSH clone init container
- `inject-repo-clone-read` (read, sre) -- HTTPS clone init container

`RENOVATE_MCP_AUTH_TOKEN` is not present in any rule. The Kyverno side is complete. No action required.

**Remaining:** Verify whether `renovate-mcp-auth-token` key still exists in `mcp-credentials.sops.yaml`. If so, the user should remove it manually: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml`. Status of this SOPS key removal is unknown -- flag to user for verification.

______________________________________________________________________

### Task 6: Add agent-platform MCP Server Entry

MCP configs are now split per-namespace. The `agent-platform` server must be added to the read and write namespace configs. SRE agents do not use platform handoff, so `claude-mcp-config-sre.yaml` is NOT modified.

**Files:**

- Modify: `cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml`

- Modify: `cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml`

- [ ] **Step 1: Add agent-platform entry to read namespace MCP config**

Add to the `mcpServers` object in the `mcp.json` data field of `claude-mcp-config-read.yaml`:

```json
        "agent-platform": {
          "type": "http",
          "url": "http://n8n-webhook.n8n-system.svc/mcp/agent-platform",
          "headers": {
            "Authorization": "Bearer $${AGENT_PLATFORM_MCP_AUTH_TOKEN}"
          }
        }
```

Note: `$${}` prevents Flux variable substitution -- env var resolved at runtime by Claude Code.

- [ ] **Step 2: Add agent-platform entry to write namespace MCP config**

Add the same `agent-platform` block to `claude-mcp-config-write.yaml`.

- [ ] **Step 3: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/claude-agents-shared/base/ > /dev/null
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml \
       cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml
git commit -m "feat(agents): add agent-platform MCP server to read and write configs

Platform agents report results via n8n MCP endpoint. Added to read and
write namespace configs (not SRE -- SRE agents don't use platform handoff).
Auth via AGENT_PLATFORM_MCP_AUTH_TOKEN env var (Kyverno-injected, SOPS-stored).

Ref #<issue>"
```

______________________________________________________________________

### Task 7: Add AGENT_PLATFORM_MCP_AUTH_TOKEN to Kyverno Injection

The old `inject-write-config` and `inject-read-config` rules no longer exist. The env var must be injected via the current per-namespace rules.

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`

**Prerequisite:** User must first add `agent-platform-mcp-auth-token` key to `mcp-credentials.sops.yaml` (manual SOPS operation). Flag this before proceeding.

- [ ] **Step 1: Flag SOPS prerequisite to user**

Tell the user: "Before this change can be deployed, add a new key `agent-platform-mcp-auth-token` to `cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml` with a generated secret value. Run: `sops cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml` and add the key."

**CRITICAL ORDERING:** This commit MUST NOT be pushed until the user confirms `agent-platform-mcp-auth-token` exists in `mcp-credentials.sops.yaml`. Pushing this Kyverno change without the SOPS key causes ALL agent pods to fail with `CreateContainerConfigError`. Same failure mode as Task 5's two-commit ordering.

- [ ] **Step 2: Add env var injection to read and write Kyverno rules**

Add to the `inject-read-mcp` and `inject-write-mcp` rules, in the `containers[*].env` list (same pattern as `SRE_MCP_AUTH_TOKEN` in `inject-sre-mcp`):

```yaml
                  - name: AGENT_PLATFORM_MCP_AUTH_TOKEN
                    valueFrom:
                      secretKeyRef:
                        name: mcp-credentials
                        key: agent-platform-mcp-auth-token
```

Do NOT add to `inject-sre-mcp` (SRE agents don't use agent-platform). Do NOT add to `inject-shared-config` (not all namespaces need it).

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "feat(agents): inject AGENT_PLATFORM_MCP_AUTH_TOKEN via Kyverno

Add env var injection for agent-platform MCP auth token to inject-read-mcp
and inject-write-mcp rules. Not added to inject-sre-mcp (SRE agents don't
use platform handoff). Requires agent-platform-mcp-auth-token key in
mcp-credentials SOPS secret.

Ref #<issue>"
```

______________________________________________________________________

### Task 8: Add Init Container SecurityContext to Kyverno Policy

Defense-in-depth: explicit securityContext on git-clone init containers.

The old `inject-repo-clone` rule has been split into two rules:

- `inject-repo-clone-write` -- SSH clone (write namespace)
- `inject-repo-clone-read` -- HTTPS clone (read and sre namespaces)

Both need securityContext added.

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`

- [ ] **Step 1: Read both inject-repo-clone rules**

Find the `inject-repo-clone-write` and `inject-repo-clone-read` rules in the Kyverno policy. Locate the init container definition in each.

- [ ] **Step 2: Add securityContext to both init containers**

Add `securityContext` to the init container spec in both `inject-repo-clone-write` and `inject-repo-clone-read`:

```yaml
                securityContext:
                  allowPrivilegeEscalation: false
                  readOnlyRootFilesystem: false
                  capabilities:
                    drop:
                      - ALL
                  runAsNonRoot: true
```

`readOnlyRootFilesystem: false` because both init containers write to `/tmp` (SSH key operations for write, HTTPS clone for read).

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml
git commit -m "fix(agents): add explicit securityContext to git-clone init containers

Defense-in-depth for PSS compliance on both inject-repo-clone-write (SSH)
and inject-repo-clone-read (HTTPS) rules. Eliminates dependency on Kyverno
pss-restricted-defaults reinvocation ordering.

Ref #<issue>"
```

______________________________________________________________________

### Task 9: Create agent-worker-system Namespace

**Files:**

- Create: `cluster/apps/agent-worker-system/namespace.yaml`

- Create: `cluster/apps/agent-worker-system/kustomization.yaml`

- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create namespace.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/namespace-v1.json
apiVersion: v1
kind: Namespace
metadata:
  name: agent-worker-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

Write to `cluster/apps/agent-worker-system/namespace.yaml`.

- [ ] **Step 2: Create top-level kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
```

Write to `cluster/apps/agent-worker-system/kustomization.yaml`. App ks.yaml references will be added as apps are created.

- [ ] **Step 3: Register in top-level kustomization**

Add `- ./agent-worker-system` to the `resources` list in `cluster/apps/kustomization.yaml` (after `- ./claude-agents-sre`):

```yaml
  - ./claude-agents-sre
  - ./agent-worker-system
```

Without this entry, Flux will never discover or reconcile the namespace.

- [ ] **Step 4: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/agent-worker-system/ > /dev/null
```

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/agent-worker-system/namespace.yaml \
       cluster/apps/agent-worker-system/kustomization.yaml \
       cluster/apps/kustomization.yaml
git commit -m "feat(agent-worker): create agent-worker-system namespace

Restricted PSA, descheduler excluded (single-replica worker).
Register in top-level kustomization so Flux discovers the namespace.

Ref #<issue>"
```

______________________________________________________________________

### Task 10: Deploy Agent Valkey Instance

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-valkey/ks.yaml`

- Create: `cluster/apps/agent-worker-system/agent-valkey/app/kustomization.yaml`

- Create: `cluster/apps/agent-worker-system/agent-valkey/app/kustomizeconfig.yaml`

- Create: `cluster/apps/agent-worker-system/agent-valkey/app/release.yaml`

- Create: `cluster/apps/agent-worker-system/agent-valkey/app/values.yaml`

- Create: `cluster/apps/agent-worker-system/agent-valkey/app/valkey-secrets.sops.yaml` (user creates)

- Create: `cluster/apps/agent-worker-system/agent-valkey/app/vpa.yaml`

- Modify: `cluster/apps/agent-worker-system/kustomization.yaml`

- [ ] **Step 1: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app agent-valkey
  namespace: flux-system
spec:
  targetNamespace: agent-worker-system
  path: ./cluster/apps/agent-worker-system/agent-valkey/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  prune: true
  timeout: 5m
```

Write to `cluster/apps/agent-worker-system/agent-valkey/ks.yaml`.

- [ ] **Step 2: Create app/release.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agent-valkey
spec:
  chart:
    spec:
      chart: valkey
      version: 0.9.4
      sourceRef:
        kind: HelmRepository
        name: valkey-io-charts
        namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: agent-valkey-values
```

Write to `cluster/apps/agent-worker-system/agent-valkey/app/release.yaml`.

- [ ] **Step 3: Create app/values.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/valkey-io/valkey-helm/refs/heads/main/valkey/values.schema.json
priorityClassName: high-priority
auth:
  enabled: true
  usersExistingSecret: agent-valkey-secrets
  aclUsers:
    default:
      permissions: "~* &* +@all"
valkeyConfig: |
  appendonly yes
  appendfsync everysec
  no-appendfsync-on-rewrite yes
  maxmemory 50mb
  maxmemory-policy noeviction
dataStorage:
  enabled: true
  requestedSize: 1Gi
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
  exporter:
    extraEnvs:
      REDIS_PASSWORD_FILE: /secrets/valkey/default-password
    extraExporterSecrets:
      - name: agent-valkey-secrets
    extraVolumeMounts:
      - name: agent-valkey-secrets-exporter
        mountPath: /secrets/valkey
        readOnly: true
resources:
  limits:
    memory: 128Mi
  requests:
    cpu: 10m
    memory: 64Mi
```

Write to `cluster/apps/agent-worker-system/agent-valkey/app/values.yaml`.

Note: No CPU limit per cluster patterns. Single consumer — default user with full permissions. Exporter reads password from file-mounted secret (no dedicated metrics ACL user).

- [ ] **Step 4: Create app/kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
  - ./valkey-secrets.sops.yaml
  - ./vpa.yaml
configMapGenerator:
  - name: agent-valkey-values
    namespace: agent-worker-system
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

Write to `cluster/apps/agent-worker-system/agent-valkey/app/kustomization.yaml`.

- [ ] **Step 5: Create app/kustomizeconfig.yaml**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

Write to `cluster/apps/agent-worker-system/agent-valkey/app/kustomizeconfig.yaml`.

- [ ] **Step 6: Create app/vpa.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: agent-valkey
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-valkey
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: valkey
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 128Mi
```

Write to `cluster/apps/agent-worker-system/agent-valkey/app/vpa.yaml`.

- [ ] **Step 7: Flag SOPS secret creation for user**

Tell the user: "Create `cluster/apps/agent-worker-system/agent-valkey/app/valkey-secrets.sops.yaml` with keys matching the existing Valkey secret pattern from `cluster/apps/valkey-system/valkey/app/valkey-secrets.sops.yaml`. Only need `default` user (no metrics ACL user — exporter uses default user credentials). Generate unique passwords."

- [ ] **Step 8: Add agent-valkey to top-level kustomization**

In `cluster/apps/agent-worker-system/kustomization.yaml`, add the ks.yaml reference:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./agent-valkey/ks.yaml
```

- [ ] **Step 9: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/agent-worker-system/agent-valkey/app/ > /dev/null
```

Expected: may warn about missing SOPS file but kustomization structure is valid.

- [ ] **Step 10: Commit**

```bash
git add cluster/apps/agent-worker-system/agent-valkey/ \
       cluster/apps/agent-worker-system/kustomization.yaml
git commit -m "feat(agent-worker): deploy dedicated agent Valkey instance

AOF persistence with Ceph-backed PVC (1Gi). maxmemory 50mb, noeviction.
Single consumer, default user auth. Redis-exporter sidecar for metrics.
Isolated from shared Valkey — agent coordination state survives restarts.

Ref #<issue>"
```

______________________________________________________________________

### Task 11: Worker CNPs — agent-worker-system Namespace

**Cross-phase note:** Tasks 11, 17, 18, 19, 20, and 21 create files in the worker app directory (`cluster/apps/agent-worker-system/agent-queue-worker/app/`). These files are committed together with Phase 1B worker app files since a partial kustomization referencing missing files would fail Flux reconciliation. The files are defined here because their content (CNPs, alerts, RBAC) is
infrastructure-scoped.

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/network-policies.yaml`

Note: This file is created now but deployed as part of the worker app kustomization. The worker app directory structure is set up in Phase 1B (HelmRelease). For now, create the CNP file and it will be referenced in the kustomization later.

- [ ] **Step 1: Create network-policies.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to agent Valkey (namespace-local)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-valkey-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: agent-worker-system
            k8s:app.kubernetes.io/name: agent-valkey
      toPorts:
        - ports:
            - port: "6379"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to n8n webhook for dispatch
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-n8n-dispatch-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
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
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to GitHub API (stale SHA checks, startup reconciliation)
# Requires companion DNS L7 rule below for Cilium FQDN cache population
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-github-api-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
  egress:
    - toFQDNs:
        - matchName: api.github.com
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s:k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
          rules:
            dns:
              - matchPattern: "*"
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from n8n (job submission, callbacks)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-n8n-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: n8n-system
            k8s:app.kubernetes.io/instance: n8n
            k8s:app.kubernetes.io/name: n8n
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow metrics scraping from vmagent
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-metrics-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Traefik (Bull Board UI)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-traefik-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: traefik
            k8s:app.kubernetes.io/name: traefik
      toPorts:
        - ports:
            - port: "3001"
              protocol: TCP
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/network-policies.yaml`.

- [ ] **Step 2: Do NOT commit yet**

This file will be committed as part of the worker app structure in Phase 1B.

______________________________________________________________________

### Task 12: Update n8n CNPs — Worker Ingress + Egress

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/network-policies.yaml`

- [ ] **Step 1: Add ingress rule for worker dispatch**

Append to `cluster/apps/n8n-system/n8n/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from agent-queue-worker for dispatch webhook
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-agent-worker-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: n8n
      app.kubernetes.io/name: n8n
      app.kubernetes.io/type: webhook
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: agent-worker-system
            k8s:app.kubernetes.io/instance: agent-queue-worker
            k8s:app.kubernetes.io/name: agent-queue-worker
      toPorts:
        - ports:
            - port: "5678"
              protocol: TCP
```

- [ ] **Step 2: Add egress rule for n8n callbacks to worker**

Append to the same file:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to agent-queue-worker for job callbacks (/jobs/:id/done, /jobs/:id/fail)
# Selects all n8n pod types — queue mode offloads executions to worker pods,
# so callbacks can originate from either webhook or worker pod types
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-agent-worker-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: n8n
      app.kubernetes.io/name: n8n
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: agent-worker-system
            k8s:app.kubernetes.io/instance: agent-queue-worker
            k8s:app.kubernetes.io/name: agent-queue-worker
      toPorts:
        - ports:
            - port: "3000"
              protocol: TCP
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/network-policies.yaml
git commit -m "feat(n8n): add CNPs for agent-queue-worker bidirectional traffic

Ingress: worker dispatch → n8n webhook (port 5678, webhook pods only).
Egress: n8n callbacks → worker (port 3000, all n8n pod types — queue mode
offloads executions to worker pods). Without egress, n8n cannot call
/jobs/:id/done and queue blocks permanently.

Ref #<issue>"
```

______________________________________________________________________

### Task 13: Add Agent-Platform MCP Egress to Agent CNPs

Agent pods need to reach the agent-platform MCP endpoint on n8n (`http://n8n-webhook.n8n-system.svc:5678/mcp/agent-platform`).

**Current state:** The `allow-n8n-mcp-egress` CNP exists only in the SRE namespace -- it is NOT in the shared base network policies. Read and write namespaces do NOT have egress to `n8n-webhook.n8n-system.svc:5678`. A new CNP must be added to the shared base.

**Files:**

- Modify: `cluster/apps/claude-agents-shared/base/network-policies.yaml`

- [ ] **Step 1: Add n8n webhook egress to shared base CNPs**

Append to `cluster/apps/claude-agents-shared/base/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to n8n webhook for agent-platform MCP
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-agent-platform-mcp-egress
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

This covers all agent namespaces (read, write) via the shared base overlay. The name `allow-agent-platform-mcp-egress` avoids collision with SRE's existing `allow-n8n-mcp-egress` CNP (at `cluster/apps/claude-agents-sre/claude-agents/app/network-policies.yaml`), which provides equivalent coverage for SRE agents -- both target n8n webhook pods on port 5678. The duplicate egress is harmless but could
be consolidated in a future cleanup by removing SRE's local CNP once the shared base policy is deployed.

> **Note:** SRE's existing `allow-n8n-mcp-egress` is NOT removed here. It predates this shared base policy and the overlap is benign. A future chore task can consolidate it.

- [ ] **Step 2: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/claude-agents-shared/base/ > /dev/null
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/claude-agents-shared/base/network-policies.yaml
git commit -m "feat(agents): add agent-platform MCP egress CNP to shared base

Read and write agent namespaces need egress to n8n-webhook.n8n-system.svc:5678
for the agent-platform MCP endpoint. SRE already has its own n8n MCP egress.

Ref #<issue>"
```

______________________________________________________________________

### Task 14: Kyverno Policies — Agent Pod Deadline

**Files:**

- Create: `cluster/apps/kyverno/policies/app/set-agent-deadline.yaml`

- Create: `cluster/apps/kyverno/policies/app/validate-agent-deadline.yaml`

- Modify: `cluster/apps/kyverno/policies/app/kustomization.yaml`

- [ ] **Step 1: Create set-agent-deadline.yaml (mutation policy)**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kyverno.io/clusterpolicy_v1.json
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: set-agent-deadline
  annotations:
    policies.kyverno.io/title: Set Agent Pod Deadline
    policies.kyverno.io/description: >-
      Sets activeDeadlineSeconds on agent pods based on the agent-timeout
      annotation. Prevents orphaned agent pods from running indefinitely.
spec:
  background: false
  webhookConfiguration:
    timeoutSeconds: 10
  rules:
    - name: set-agent-deadline
      match:
        any:
          - resources:
              kinds:
                - Pod
              selector:
                matchLabels:
                  managed-by: n8n-claude-code
      mutate:
        patchStrategicMerge:
          spec:
            activeDeadlineSeconds: "{{ to_number(request.object.metadata.annotations.\"agent-timeout\" || `1740`) }}"
```

Write to `cluster/apps/kyverno/policies/app/set-agent-deadline.yaml`.

- [ ] **Step 2: Create validate-agent-deadline.yaml (validation policy)**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kyverno.io/clusterpolicy_v1.json
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-agent-deadline
  annotations:
    policies.kyverno.io/title: Validate Agent Pod Deadline
    policies.kyverno.io/description: >-
      Rejects agent pods that do not have activeDeadlineSeconds set.
      Safety net for mutation policy failure.
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: require-active-deadline
      match:
        any:
          - resources:
              kinds:
                - Pod
              selector:
                matchLabels:
                  managed-by: n8n-claude-code
      validate:
        message: "Agent pods must have activeDeadlineSeconds set. Check set-agent-deadline mutation policy."
        pattern:
          spec:
            activeDeadlineSeconds: ">=1"
```

Write to `cluster/apps/kyverno/policies/app/validate-agent-deadline.yaml`.

- [ ] **Step 3: Add to kustomization.yaml**

Read `cluster/apps/kyverno/policies/app/kustomization.yaml` and add both new files to the `resources` list:

```yaml
  - ./set-agent-deadline.yaml
  - ./validate-agent-deadline.yaml
```

- [ ] **Step 4: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/kyverno/policies/app/ > /dev/null
```

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/kyverno/policies/app/set-agent-deadline.yaml \
       cluster/apps/kyverno/policies/app/validate-agent-deadline.yaml \
       cluster/apps/kyverno/policies/app/kustomization.yaml
git commit -m "feat(kyverno): add agent pod deadline mutation and validation

Mutation: sets activeDeadlineSeconds from agent-timeout annotation (default
1740s). Validation: rejects agent pods without activeDeadlineSeconds (fail-
closed on mutation miss). Both target managed-by: n8n-claude-code label.

Ref #<issue>"
```

______________________________________________________________________

### Task 15: Kyverno ClusterCleanupPolicy — Agent Pod Garbage Collection

**Files:**

- Create: `cluster/apps/kyverno/policies/app/cleanup-agent-pods.yaml`

- Modify: `cluster/apps/kyverno/policies/app/kustomization.yaml`

- [ ] **Step 1: Create cleanup-agent-pods.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kyverno.io/clustercleanuppolicy_v2.json
apiVersion: kyverno.io/v2
kind: ClusterCleanupPolicy
metadata:
  name: cleanup-agent-pods
  annotations:
    policies.kyverno.io/title: Cleanup Completed Agent Pods
    policies.kyverno.io/description: >-
      Removes completed/failed agent pods that n8n failed to clean up.
      Defense-in-depth — normal path deletes pods immediately.
spec:
  schedule: "0 * * * *"
  match:
    any:
      - resources:
          kinds:
            - Pod
          selector:
            matchLabels:
              managed-by: n8n-claude-code
  conditions:
    any:
      - key: "{{ request.object.status.phase }}"
        operator: AnyIn
        value:
          - Succeeded
          - Failed
```

Write to `cluster/apps/kyverno/policies/app/cleanup-agent-pods.yaml`.

- [ ] **Step 2: Add to kustomization.yaml**

Add `./cleanup-agent-pods.yaml` to the `resources` list.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/cleanup-agent-pods.yaml \
       cluster/apps/kyverno/policies/app/kustomization.yaml
git commit -m "feat(kyverno): add ClusterCleanupPolicy for orphaned agent pods

Hourly cleanup of completed/failed agent pods with managed-by: n8n-claude-code
label. Defense-in-depth — n8n's k8sEphemeral mode normally deletes pods.

Ref #<issue>"
```

______________________________________________________________________

### Task 16: Descheduler Namespace Exclusions

**Files:**

- Modify: `cluster/apps/kube-system/descheduler/app/values.yaml`

- [ ] **Step 1: Add agent-worker-system to all 5 exclusion lists**

Read `cluster/apps/kube-system/descheduler/app/values.yaml`. Add `- agent-worker-system` to each of the 5 per-plugin `namespaces.exclude` lists:

1. `RemoveDuplicates`
1. `RemovePodsViolatingTopologySpreadConstraint`
1. `RemoveFailedPods`
1. `RemovePodsHavingTooManyRestarts`
1. `LowNodeUtilization` (under `evictableNamespaces.exclude`)

No `claude-agents-read` entry exists in the exclude lists -- agent namespaces are intentionally NOT excluded (only core infra namespaces are: kube-system, kube-public, kube-node-lease, flux-system, rook-ceph, cloudflare-system). Add `- agent-worker-system` after the last existing entry (`cloudflare-system`) in each list.

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "chore(descheduler): exclude agent-worker-system namespace

Single-replica worker — eviction causes unnecessary downtime.

Ref #<issue>"
```

______________________________________________________________________

### Task 17: VMRule Alerts

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/vmrule.yaml`

Note: Deployed as part of worker app kustomization in Phase 1B.

- [ ] **Step 1: Create vmrule.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/operator.victoriametrics.com/vmrule_v1beta1.json
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: agent-queue-worker
spec:
  groups:
    - name: agent-queue-worker
      rules:
        - alert: AgentWorkerCrashLooping
          expr: |
            increase(kube_pod_container_status_restarts_total{
              namespace="agent-worker-system",
              container="app"
            }[15m]) >= 3
          for: 0m
          labels:
            severity: critical
          annotations:
            summary: "Agent queue worker is crash-looping"
            description: "Worker pod has restarted {{ $value }} times in 15 minutes."
        - alert: AgentQueueStuck
          expr: |
            agent_queue_depth{queue="agent"} > 0
          for: 75m
          labels:
            severity: warning
          annotations:
            summary: "Agent queue has jobs stuck for >75 minutes"
            description: "Queue depth {{ $value }} sustained for 75+ minutes (max role timeout + buffer)."
        - alert: AgentValkeyMemoryHigh
          expr: |
            redis_memory_used_bytes{namespace="agent-worker-system"} /
            redis_memory_max_bytes{namespace="agent-worker-system"} > 0.8
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Agent Valkey memory usage >80%"
            description: "Usage at {{ $value | humanizePercentage }}. noeviction will fail writes at 100%."
        - alert: AgentValkeyAOFError
          expr: |
            redis_aof_last_write_status{namespace="agent-worker-system"} != 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Agent Valkey AOF write errors"
            description: "AOF persistence is failing — coordination state may not survive restart."
        - alert: AgentJobExhausted
          expr: |
            increase(agent_job_exhausted_total[1h]) > 0
          for: 0m
          labels:
            severity: warning
          annotations:
            summary: "Agent job exhausted all retry attempts"
            description: "Job in repo={{ $labels.repo }} role={{ $labels.role }} failed after all retries."
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/vmrule.yaml`.

Note: The spec uses `redis_aof_last_write_status != 0` but redis_exporter returns 1 for success, so `!= 1` is correct. Spec will be updated.

- [ ] **Step 2: Do NOT commit yet**

This file will be committed as part of the worker app structure in Phase 1B.

______________________________________________________________________

### Task 18: Worker App Directory Structure (Skeleton for Phase 1B)

Create the directory structure for the worker app. Phase 1B fills in the HelmRelease, values, and TypeScript source.

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/ks.yaml`

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/kustomization.yaml`

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/kustomizeconfig.yaml`

- Modify: `cluster/apps/agent-worker-system/kustomization.yaml`

- [ ] **Step 1: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app agent-queue-worker
  namespace: flux-system
spec:
  targetNamespace: agent-worker-system
  path: ./cluster/apps/agent-worker-system/agent-queue-worker/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: agent-valkey
    - name: n8n
  prune: true
  timeout: 5m
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/ks.yaml`.

- [ ] **Step 2: Create app/kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
  - ./network-policies.yaml
  - ./vmrule.yaml
  - ./vpa.yaml
  - ./secret-reader-rbac.yaml
configMapGenerator:
  - name: agent-queue-worker-values
    namespace: agent-worker-system
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/kustomization.yaml`.

- [ ] **Step 3: Create app/kustomizeconfig.yaml**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/kustomizeconfig.yaml`.

- [ ] **Step 4: Add worker to top-level kustomization**

In `cluster/apps/agent-worker-system/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./agent-valkey/ks.yaml
  - ./agent-queue-worker/ks.yaml
```

- [ ] **Step 5: Do NOT commit yet**

The worker app skeleton is committed together with remaining Phase 1B files (release.yaml, values.yaml, vpa.yaml, ExternalSecrets) since a partial kustomization referencing missing files would fail Flux reconciliation.

______________________________________________________________________

### Task 19: ExternalSecrets — Cross-Namespace Secret Sync to n8n

Worker auth secrets must be accessible in both `agent-worker-system` and `n8n-system` namespaces.

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/secret-store.yaml`
- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/externalsecret.yaml`

Note: The worker secrets SOPS file lives directly in the worker app directory (same namespace). ExternalSecrets syncs specific keys to n8n namespace. However, since the worker secrets are in the same namespace as the worker, we don't need a SecretStore for the worker itself — only n8n needs access.

Actually, the simpler pattern is: SOPS secret in the worker namespace has all 4 keys. For n8n to access the bidirectional auth secrets, we add an ExternalSecret in the n8n namespace that pulls from the worker namespace. This means the ExternalSecret + SecretStore go in the n8n app directory, not the worker directory.

- [ ] **Step 1: Reconsider architecture**

The bidirectional auth secrets (`WORKER_TO_N8N_SECRET`, `N8N_TO_WORKER_SECRET`) need to be in both namespaces. Two options:

**Option A:** SOPS secret in worker namespace + ExternalSecret in n8n namespace pulling from worker namespace. **Option B:** Shared SOPS secret committed to both app directories.

Option A follows the existing pattern (github-secret-store.yaml in claude-agents-shared). Use Option A.

- [ ] **Step 2: Create SecretStore in n8n for reading from agent-worker-system**

This requires a ServiceAccount + RoleBinding in agent-worker-system that allows the n8n ExternalSecrets SA to read secrets. However, adding resources to n8n-system's app directory is the cleaner approach. Check existing patterns first.

The existing `github-secret-store.yaml` in `claude-agents-shared/base/` creates a SecretStore per namespace that reads from `github-system`. Following this pattern:

Create `cluster/apps/n8n-system/n8n/app/agent-worker-secret-store.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: agent-worker-secret-reader
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/secretstore_v1.json
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: agent-worker-secret-store
spec:
  provider:
    kubernetes:
      remoteNamespace: agent-worker-system
      server:
        url: "https://kubernetes.default.svc"
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: agent-worker-secret-reader
```

**Important:** This also requires a Role + RoleBinding in `agent-worker-system` granting the ServiceAccount read access to secrets. Create RBAC in the worker app directory.

- [ ] **Step 3: Create RBAC for cross-namespace secret reading**

Create `cluster/apps/agent-worker-system/agent-queue-worker/app/secret-reader-rbac.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: agent-worker-secret-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "watch"]
    resourceNames: ["agent-queue-worker-secrets"]
  - apiGroups: ["authorization.k8s.io"]
    resources: ["selfsubjectrulesreviews"]
    verbs: ["create"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: agent-worker-secret-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: agent-worker-secret-reader
subjects:
  - kind: ServiceAccount
    name: agent-worker-secret-reader
    namespace: n8n-system
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/secret-reader-rbac.yaml`.

- [ ] **Step 4: Create ExternalSecret in n8n namespace**

Create `cluster/apps/n8n-system/n8n/app/agent-worker-external-secret.yaml`:

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: agent-worker-auth
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: agent-worker-secret-store
    kind: SecretStore
  target:
    name: agent-worker-auth
    creationPolicy: Owner
  data:
    - secretKey: WORKER_TO_N8N_SECRET
      remoteRef:
        key: agent-queue-worker-secrets
        property: WORKER_TO_N8N_SECRET
    - secretKey: N8N_TO_WORKER_SECRET
      remoteRef:
        key: agent-queue-worker-secrets
        property: N8N_TO_WORKER_SECRET
```

Write to `cluster/apps/n8n-system/n8n/app/agent-worker-external-secret.yaml`.

- [ ] **Step 5: Add new files to n8n kustomization**

Read `cluster/apps/n8n-system/n8n/app/kustomization.yaml` and add:

```yaml
  - ./agent-worker-secret-store.yaml
  - ./agent-worker-external-secret.yaml
```

- [ ] **Step 6: Do NOT commit yet**

These files depend on Phase 1B (worker SOPS secret must exist). Committed together with Phase 1B.

**Deployment ordering:** The ExternalSecret (n8n namespace), SecretStore + ServiceAccount (n8n namespace), RBAC Role/RoleBinding (worker namespace), and worker SOPS secret must all deploy in the same push. The ExternalSecret will retry on transient failures, but the RBAC and source secret must exist for the sync to succeed.

______________________________________________________________________

### Task 20: Worker SOPS Secret (User Operation)

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/agent-queue-worker-secrets.sops.yaml` (user creates)

- [ ] **Step 1: Flag to user**

Tell the user: "Create the worker SOPS secret with these keys:

```bash
sops cluster/apps/agent-worker-system/agent-queue-worker/app/agent-queue-worker-secrets.sops.yaml
```

Required keys:

- `VALKEY_PASSWORD` — same password value as agent-valkey-secrets.sops.yaml `default-password` key, but stored under `VALKEY_PASSWORD` for env var injection via `envFrom: secretRef`
- `GITHUB_TOKEN` — fine-grained PAT with `pull_requests:read` + `checks:read` scope (public repos only)
- `WORKER_TO_N8N_SECRET` — generate: `openssl rand -hex 32`
- `N8N_TO_WORKER_SECRET` — generate: `openssl rand -hex 32`

Template:

````yaml
apiVersion: v1
kind: Secret
metadata:
  name: agent-queue-worker-secrets
stringData:
  VALKEY_PASSWORD: <same-as-agent-valkey-default-password>
  GITHUB_TOKEN: <fine-grained-pat>
  WORKER_TO_N8N_SECRET: <generated-hex>
  N8N_TO_WORKER_SECRET: <generated-hex>
```"

- [ ] **Step 2: After user creates, add to worker kustomization resources**

```yaml
  - ./agent-queue-worker-secrets.sops.yaml
````

______________________________________________________________________

### Task 21: Worker VPA

**Note:** This task defines the VPA content for reference. The actual file creation and commit happens in **Phase 1B Task 15 Step 2** to avoid duplicate file creation. Implementers executing Phase 1B should use the content below.

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/vpa.yaml` **(created in Phase 1B Task 15)**

- [ ] **Step 1: VPA content (created in Phase 1B Task 15)**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: agent-queue-worker-worker
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-queue-worker-worker
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 128Mi
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: agent-queue-worker-bull-board
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-queue-worker-bull-board
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 128Mi
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/vpa.yaml`.

Note: VPA `targetRef.name` uses the bjw-s app-template naming convention: `{helmrelease-name}-{controller-name}`. The HelmRelease is `agent-queue-worker` with controllers `worker` and `bull-board`, producing Deployments named `agent-queue-worker-worker` and `agent-queue-worker-bull-board`.

- [ ] **Step 2: Do NOT commit yet**

Part of Phase 1B worker app commit.

______________________________________________________________________

### Task 22: Verification Checklist (Post-Deploy)

After all Phase 1A changes are pushed and reconciled:

- [ ] **Step 1: Verify settings profiles**

```bash
kubectl get configmap claude-settings-profiles -n claude-agents-read -o jsonpath='{.data}' | jq 'keys'
```

Expected: `["execute.json", "fix.json", "sre.json", "triage.json", "validate.json"]` -- no admin, dev, or pr.

- [ ] **Step 2: Verify MCP configs (per-namespace)**

Check the read namespace config includes `agent-platform`:

```bash
kubectl get configmap claude-mcp-config-read -n claude-agents-read -o jsonpath='{.data.mcp\.json}' | jq '.mcpServers | keys'
```

Expected: includes `agent-platform`, `bravesearch`, `context7`, `github`.

Check the write namespace config includes `agent-platform`:

```bash
kubectl get configmap claude-mcp-config-write -n claude-agents-write -o jsonpath='{.data.mcp\.json}' | jq '.mcpServers | keys'
```

Expected: includes `agent-platform`, `bravesearch`, `context7`, `discord`, `github`, `kubectl`, `victoriametrics`.

Check the SRE namespace config does NOT include `agent-platform`:

```bash
kubectl get configmap claude-mcp-config-sre -n claude-agents-sre -o jsonpath='{.data.mcp\.json}' | jq '.mcpServers | keys'
```

Expected: includes `bravesearch`, `context7`, `discord`, `github`, `kubectl`, `sre`, `victoriametrics` -- does NOT include `agent-platform`.

- [ ] **Step 3: Verify agent Valkey**

```bash
kubectl get pods -n agent-worker-system -l app.kubernetes.io/name=agent-valkey
kubectl get pvc -n agent-worker-system
```

Expected: Valkey pod Running, PVC Bound with 1Gi.

- [ ] **Step 4: Verify AOF persistence**

```bash
kubectl exec -n agent-worker-system deploy/agent-valkey -- valkey-cli CONFIG GET appendonly
```

Expected: `appendonly yes`.

- [ ] **Step 5: Verify Kyverno policies**

```bash
kubectl get clusterpolicy set-agent-deadline validate-agent-deadline cleanup-agent-pods
```

Expected: all policies listed, READY.

- [ ] **Step 6: Test deadline mutation**

```bash
kubectl run test-agent --image=busybox --labels="managed-by=n8n-claude-code" --annotations="agent-timeout=540" --namespace=claude-agents-read --command -- sleep 10
kubectl get pod test-agent -n claude-agents-read -o jsonpath='{.spec.activeDeadlineSeconds}'
kubectl delete pod test-agent -n claude-agents-read
```

Expected: returns `540` (integer).

- [ ] **Step 7: Verify descheduler exclusions**

Check the descheduler values contain `agent-worker-system` in all 5 plugin exclusion lists.

- [ ] **Step 8: Verify n8n CNPs deployed**

```bash
kubectl get cnp -n n8n-system | grep agent-worker
```

Expected: `allow-agent-worker-ingress` and `allow-agent-worker-egress`.

- [ ] **Step 9: Verify Valkey alerts**

```bash
kubectl get vmrule -n agent-worker-system
```

Expected: `agent-queue-worker` rule listed (deployed with Phase 1B).

- [ ] **Step 10: Verify n8n-webhook Service has endpoints**

```bash
kubectl get endpoints n8n-webhook -n n8n-system
```

Expected: pod IPs listed (healthy webhook pods backing the Service).

- [ ] **Step 11: Note — n8n Claude Code credentials**

n8n Claude Code credentials (`claude-agent-read`, `claude-agent-write`) are created in Phase 2 Task 2. Phase 1A infrastructure is prerequisite but credentials are n8n UI operations done at dispatch time.

### Note: Mergify Setup

Mergify configuration (`.mergify.yml` per repo) is spec Phase 1 item 1 but is tracked separately — it's a per-repo file, not cluster infrastructure. Deploy alongside Phase 2 when the triage check run name (`agent/triage`) is finalized.
