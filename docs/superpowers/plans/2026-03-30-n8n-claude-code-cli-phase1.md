# Phase 1: n8n Claude Code CLI Node Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the infrastructure for n8n to spawn ephemeral Claude Code
pods in a dedicated `claude-agents` namespace with MCP connectivity and
subscription auth.

**Architecture:** n8n community node creates ephemeral pods in
`claude-agents`. Each pod bootstraps config (auth token, MCP servers,
settings) from K8s API at startup, removes kubectl, then runs `claude -p`.
Two service accounts enforce separation: spawner (creates pods) and agent
(reads config).

**Tech Stack:** Kubernetes, FluxCD, Cilium CNPs, SOPS/Age, n8n, Claude
Code CLI, Docker (container-images repo)

**Spec:** `docs/superpowers/specs/2026-03-30-n8n-claude-code-cli-phase1-design.md`
**Issue:** #823

---

## File Map

### New files (spruyt-labs repo)

| File | Responsibility |
| ---- | -------------- |
| `cluster/apps/claude-agents/namespace.yaml` | Namespace with PSA + descheduler labels |
| `cluster/apps/claude-agents/kustomization.yaml` | References namespace + app ks.yaml |
| `cluster/apps/claude-agents/claude-agents/ks.yaml` | Flux Kustomization |
| `cluster/apps/claude-agents/claude-agents/app/kustomization.yaml` | Lists all app resources |
| `cluster/apps/claude-agents/claude-agents/app/claude-credentials.sops.yaml` | SOPS secret with setup token |
| `cluster/apps/claude-agents/claude-agents/app/claude-mcp-config.yaml` | ConfigMap with .mcp.json |
| `cluster/apps/claude-agents/claude-agents/app/claude-settings.yaml` | ConfigMap with settings.json |
| `cluster/apps/claude-agents/claude-agents/app/rbac.yaml` | Agent SA + Role + RoleBinding |
| `cluster/apps/claude-agents/claude-agents/app/rbac-spawner.yaml` | Spawner SA + token + Role + RoleBinding |
| `cluster/apps/claude-agents/claude-agents/app/network-policies.yaml` | All CNPs for claude-agents namespace |
| `cluster/apps/claude-agents/claude-agents/README.md` | Component docs |

### Modified files (spruyt-labs repo)

| File | Change |
| ---- | ------ |
| `cluster/apps/kustomization.yaml` | Add `./claude-agents` entry |
| `cluster/apps/n8n-system/n8n/app/values.yaml` | Add `N8N_COMMUNITY_PACKAGES` env var |
| `cluster/apps/n8n-system/n8n/ks.yaml` | Add `dependsOn: claude-agents` |
| `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml` | Add ingress from claude-agents |
| `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | Add ingress from claude-agents |
| `cluster/apps/kube-system/descheduler/app/values.yaml` | Add claude-agents to exclude lists |

### New files (container-images repo)

| File | Responsibility |
| ---- | -------------- |
| `claude-agent/Dockerfile` | Image build definition |
| `claude-agent/assets/entrypoint.sh` | Bootstrap + exec claude |
| `claude-agent/metadata.yaml` | Image factory metadata |
| `claude-agent/test.sh` | Image smoke test |
| `claude-agent/README.md` | Image docs |

---

## Task 1: Container image (container-images repo)

> This task is in the `anthony-spruyt/container-images` repo, not spruyt-labs.

**Files:**

- Create: `claude-agent/Dockerfile`
- Create: `claude-agent/assets/entrypoint.sh`
- Create: `claude-agent/metadata.yaml`
- Create: `claude-agent/test.sh`
- Create: `claude-agent/README.md`

- [ ] **Step 1: Create metadata.yaml**

```yaml
---
version: "1.0"
auto_patch: true
```

- [ ] **Step 2: Create entrypoint.sh**

```bash
#!/bin/bash
set -euo pipefail

# Bootstrap: fetch config from K8s API
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

# Auth: static setup token (1-year lifetime, no refresh needed)
CLAUDE_CODE_OAUTH_TOKEN=$(kubectl get secret claude-credentials \
  -n "$NAMESPACE" -o jsonpath='{.data.oauth-token}' | base64 -d)
export CLAUDE_CODE_OAUTH_TOKEN

# MCP and settings config
mkdir -p ~/.claude
kubectl get configmap claude-mcp-config -n "$NAMESPACE" \
  -o jsonpath='{.data.mcp\.json}' > /workspace/.mcp.json

kubectl get configmap claude-settings -n "$NAMESPACE" \
  -o jsonpath='{.data.settings\.json}' > ~/.claude/settings.json

# Remove kubectl — agent must use MCP for K8s operations
rm -f "$(which kubectl)"

exec claude "$@"
```

- [ ] **Step 3: Create Dockerfile**

Base on the `gastown-dev` pattern but stripped down for a runtime image (not
dev container). Use `node:20-slim` as base. Install Python, git, kubectl,
Claude CLI (native installer), and Aikido safe-chain.

```dockerfile
FROM node:20-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# kubectl (for bootstrap only — removed by entrypoint before agent starts)
# renovate: depName=kubernetes/kubernetes datasource=github-releases
ARG KUBECTL_VERSION="v1.33.0"
RUN curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
      -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# Aikido safe-chain
# renovate: depName=@aikidosec/safe-chain datasource=npm
ARG SAFE_CHAIN_VERSION="1.4.4"
RUN npm install -g "@aikidosec/safe-chain@${SAFE_CHAIN_VERSION}" \
    && safe-chain setup && safe-chain setup-ci
ENV PATH="/root/.safe-chain/shims:${PATH}"

# Claude Code CLI (native installer)
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.claude/bin:${PATH}"

# Working directory
WORKDIR /workspace

# Entrypoint
COPY assets/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

**Note:** The exact Dockerfile will need iteration based on the native
installer's behavior (install path, Node.js version requirements, user
setup). The `gastown-dev` image uses devcontainer features for Node/Python —
this image is simpler and uses `node:20-slim` directly. Adjust paths and
user if PSA restricted requires `runAsNonRoot`.

- [ ] **Step 4: Create test.sh**

```bash
#!/bin/bash
set -euo pipefail

echo "Testing claude-agent image..."

# Verify core binaries exist
for bin in claude node python3 git npm kubectl; do
  if ! command -v "$bin" &>/dev/null; then
    echo "FAIL: $bin not found"
    exit 1
  fi
  echo "OK: $bin found at $(which "$bin")"
done

# Verify claude version
claude --version

# Verify safe-chain
safe-chain --version

echo "All tests passed."
```

- [ ] **Step 5: Create README.md**

Brief README covering image purpose, contents, entrypoint behavior, and
how to build locally.

- [ ] **Step 6: Commit**

```bash
git add claude-agent/
git commit -m "feat(claude-agent): add Claude Code runner image for n8n ephemeral pods

Ref anthony-spruyt/spruyt-labs#823"
```

- [ ] **Step 7: Push and verify CI builds the image**

Push to `main`. Verify the image factory CI pipeline builds and publishes
`ghcr.io/anthony-spruyt/claude-agent`. Note the image tag + digest for use
in the n8n credential config.

---

## Task 2: Namespace + Flux Kustomization

**Files:**

- Create: `cluster/apps/claude-agents/namespace.yaml`
- Create: `cluster/apps/claude-agents/kustomization.yaml`
- Create: `cluster/apps/claude-agents/claude-agents/ks.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create namespace.yaml**

```yaml
---
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

- [ ] **Step 2: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app claude-agents
  namespace: flux-system
spec:
  targetNamespace: claude-agents
  path: ./cluster/apps/claude-agents/claude-agents/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  prune: true
  timeout: 5m
  wait: true
```

- [ ] **Step 3: Create namespace kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./claude-agents/ks.yaml
```

- [ ] **Step 4: Add to top-level kustomization.yaml**

Modify `cluster/apps/kustomization.yaml` — add `./claude-agents` after
`./kubectl-mcp`:

```yaml
  - ./kubectl-mcp
  - ./claude-agents
  - ./vpa-system
```

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/claude-agents/namespace.yaml \
        cluster/apps/claude-agents/kustomization.yaml \
        cluster/apps/claude-agents/claude-agents/ks.yaml \
        cluster/apps/kustomization.yaml
git commit -m "feat(claude-agents): add namespace and Flux kustomization

Ref #823"
```

---

## Task 3: RBAC (agent SA + spawner SA)

**Files:**

- Create: `cluster/apps/claude-agents/claude-agents/app/rbac.yaml`
- Create: `cluster/apps/claude-agents/claude-agents/app/rbac-spawner.yaml`

- [ ] **Step 1: Create rbac.yaml (agent SA)**

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: claude-agent
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: claude-config-reader
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["claude-credentials"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["claude-mcp-config", "claude-settings"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: claude-agent-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: claude-config-reader
subjects:
  - kind: ServiceAccount
    name: claude-agent
    namespace: claude-agents
```

- [ ] **Step 2: Create rbac-spawner.yaml**

The spawner SA lives in `n8n-system` but the Role + RoleBinding are in
`claude-agents`. **Flux `targetNamespace` risk:** test whether Flux
overrides the SA's explicit `namespace: n8n-system`. If it does, move
the SA to `cluster/apps/n8n-system/n8n/app/` instead.

```yaml
---
# SA in n8n-system — explicit namespace to override targetNamespace
apiVersion: v1
kind: ServiceAccount
metadata:
  name: n8n-claude-spawner
  namespace: n8n-system
---
# Long-lived token for the spawner SA (used to generate kubeconfig for n8n)
apiVersion: v1
kind: Secret
metadata:
  name: n8n-claude-spawner-token
  namespace: n8n-system
  annotations:
    kubernetes.io/service-account.name: n8n-claude-spawner
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: claude-pod-manager
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "watch", "delete"]
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["pods/status"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: n8n-claude-spawner-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: claude-pod-manager
subjects:
  - kind: ServiceAccount
    name: n8n-claude-spawner
    namespace: n8n-system
```

- [ ] **Step 3: Validate kustomize build renders correctly**

Run: `kubectl kustomize cluster/apps/claude-agents/claude-agents/app/`

Verify all resources render without errors. **Note:** `kubectl kustomize`
does NOT simulate Flux's `targetNamespace` override — the SA's
`namespace: n8n-system` will appear preserved here regardless. The real
test happens post-deploy in Task 10 Step 2: verify the SA exists in
`n8n-system` (not `claude-agents`). If Flux overrides it, move the SA +
token Secret to `cluster/apps/n8n-system/n8n/app/` instead.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents/claude-agents/app/rbac.yaml \
        cluster/apps/claude-agents/claude-agents/app/rbac-spawner.yaml
git commit -m "feat(claude-agents): add RBAC for agent and spawner SAs

Ref #823"
```

---

## Task 4: Config resources (secret + configmaps)

**Files:**

- Create: `cluster/apps/claude-agents/claude-agents/app/claude-credentials.sops.yaml`
- Create: `cluster/apps/claude-agents/claude-agents/app/claude-mcp-config.yaml`
- Create: `cluster/apps/claude-agents/claude-agents/app/claude-settings.yaml`

- [ ] **Step 1: Create claude-mcp-config.yaml**

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

- [ ] **Step 2: Create claude-settings.yaml**

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: claude-settings
data:
  settings.json: |
    {
      "permissions": {
        "deny": []
      }
    }
```

- [ ] **Step 3: Create claude-credentials.sops.yaml**

**Prerequisite:** The user must have a setup token from
`claude setup-token` (run interactively, 1-year lifetime). The user
has confirmed the token is already generated.

Encrypt the setup token with SOPS:

```bash
cat > /tmp/claude-credentials.yaml << 'EOF'
---
apiVersion: v1
kind: Secret
metadata:
  name: claude-credentials
type: Opaque
stringData:
  oauth-token: "PASTE_YOUR_SETUP_TOKEN_HERE"
EOF

# User encrypts with SOPS (Age key)
sops --encrypt --in-place /tmp/claude-credentials.yaml
mv /tmp/claude-credentials.yaml \
  cluster/apps/claude-agents/claude-agents/app/claude-credentials.sops.yaml
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents/claude-agents/app/claude-mcp-config.yaml \
        cluster/apps/claude-agents/claude-agents/app/claude-settings.yaml \
        cluster/apps/claude-agents/claude-agents/app/claude-credentials.sops.yaml
git commit -m "feat(claude-agents): add config resources and credentials secret

Ref #823"
```

---

## Task 5: Network policies

**Files:**

- Create: `cluster/apps/claude-agents/claude-agents/app/network-policies.yaml`
- Modify: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`
- Modify: `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`

- [ ] **Step 1: Create network-policies.yaml for claude-agents**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kube-apiserver (bootstrap only — kubectl removed after)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
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
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow all egress to world — agents need external APIs, npm, git, etc.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-world-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: claude-agent
  egress:
    - toEntities:
        - world
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

- [ ] **Step 2: Add ingress to kubectl-mcp network-policies.yaml**

Add a new CNP to
`cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`
after the existing `allow-openclaw-ingress`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agents (pod-to-pod MCP access)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubectl-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents
            k8s:app.kubernetes.io/name: claude-agent
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

- [ ] **Step 3: Add ingress to mcp-victoriametrics network-policies.yaml**

Add a new CNP to
`cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`
after the existing `allow-openclaw-ingress`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Claude agents (pod-to-pod MCP access)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-claude-agents-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-victoriametrics
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: claude-agents
            k8s:app.kubernetes.io/name: claude-agent
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents/claude-agents/app/network-policies.yaml \
        cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml \
        cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml
git commit -m "feat(claude-agents): add network policies for MCP access

Ref #823"
```

---

## Task 6: Descheduler exclusion

**Files:**

- Modify: `cluster/apps/kube-system/descheduler/app/values.yaml`

- [ ] **Step 1: Add claude-agents to all exclude lists**

Add `- claude-agents` to each of the five `namespaces.exclude` /
`evictableNamespaces.exclude` lists in the descheduler values. Each list
currently ends with `- vpa-system`. Add `- claude-agents` after it in all
five locations:

1. `RemoveDuplicates.namespaces.exclude`
2. `RemovePodsViolatingTopologySpreadConstraint.namespaces.exclude`
3. `RemoveFailedPods.namespaces.exclude`
4. `RemovePodsHavingTooManyRestarts.namespaces.exclude`
5. `LowNodeUtilization.evictableNamespaces.exclude`

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "chore(descheduler): exclude claude-agents namespace

Ref #823"
```

---

## Task 7: App kustomization + README

**Files:**

- Create: `cluster/apps/claude-agents/claude-agents/app/kustomization.yaml`
- Create: `cluster/apps/claude-agents/claude-agents/README.md`

- [ ] **Step 1: Create app kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./claude-credentials.sops.yaml
  - ./claude-mcp-config.yaml
  - ./claude-settings.yaml
  - ./rbac.yaml
  - ./rbac-spawner.yaml
  - ./network-policies.yaml
```

- [ ] **Step 2: Create README.md**

Write using the template from `docs/templates/readme_template.md`. Cover:

- Overview: ephemeral Claude Code agent pods for n8n workflows
- Prerequisites: n8n, kubectl-mcp, mcp-victoriametrics
- Operation: how pods are spawned, config bootstrap, kubectl removal
- Troubleshooting: pod stuck pending, auth failures, MCP unreachable
- References: spec doc, issue #823, community node repo

- [ ] **Step 3: Validate kustomize build**

Run: `kubectl kustomize cluster/apps/claude-agents/claude-agents/app/`

Verify all resources render correctly without errors.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/claude-agents/claude-agents/app/kustomization.yaml \
        cluster/apps/claude-agents/claude-agents/README.md
git commit -m "feat(claude-agents): add app kustomization and README

Ref #823"
```

---

## Task 8: n8n changes (community node + dependency)

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml`
- Modify: `cluster/apps/n8n-system/n8n/ks.yaml`

- [ ] **Step 1: Add community node env var to values.yaml**

Add `N8N_COMMUNITY_PACKAGES` to the `main.extraEnv` block (which
propagates to worker and webhook via `*extraEnv` anchor). Add after the
existing `WEBHOOK_URL` entry (around line 111):

```yaml
    N8N_COMMUNITY_PACKAGES:
      value: "n8n-nodes-claude-code-cli"
```

- [ ] **Step 2: Add dependsOn to ks.yaml**

Add `- name: claude-agents` to the `dependsOn` list in
`cluster/apps/n8n-system/n8n/ks.yaml`:

```yaml
  dependsOn:
    - name: authentik
    - name: cnpg-operator
    - name: plugin-barman-cloud
    - name: valkey
    - name: claude-agents
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/values.yaml \
        cluster/apps/n8n-system/n8n/ks.yaml
git commit -m "feat(n8n): install Claude Code CLI community node and depend on claude-agents

Ref #823"
```

---

## Task 9: Pre-commit validation

- [ ] **Step 1: Run qa-validator**

Run the qa-validator agent on all changed files before pushing. This
catches YAML lint, schema validation, and other issues.

- [ ] **Step 2: Fix any issues found**

Address any lint or schema errors, re-run qa-validator until clean.

- [ ] **Step 3: Push to main**

User pushes manually (no git push by Claude).

---

## Task 10: Post-deploy validation + n8n credential config

> This task happens AFTER the user pushes to main and Flux reconciles.

- [ ] **Step 1: Run cluster-validator**

Run the cluster-validator agent to verify all resources reconcile cleanly.

- [ ] **Step 2: Verify namespace and resources exist**

Check that the `claude-agents` namespace is created with all expected
resources: SA, Role, RoleBinding, ConfigMaps, Secret, CNPs.

**Critical: verify spawner SA namespace.** Run:
`kubectl get sa n8n-claude-spawner -n n8n-system`

If this fails (SA was created in `claude-agents` instead due to Flux
`targetNamespace` override), move the SA + token Secret to
`cluster/apps/n8n-system/n8n/app/`, remove from `rbac-spawner.yaml`,
re-push, and re-validate.

- [ ] **Step 3: Verify n8n restarts with community node**

Check that n8n pods restart and the community node is installed. Look for
`n8n-nodes-claude-code-cli` in n8n logs.

- [ ] **Step 4: Generate spawner kubeconfig**

Generate a kubeconfig for the `n8n-claude-spawner` SA using the long-lived
token from the `n8n-claude-spawner-token` Secret. This kubeconfig will be
pasted into n8n's credential UI:

```bash
# Get the token and CA cert
TOKEN=$(kubectl get secret n8n-claude-spawner-token -n n8n-system \
  -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl get secret n8n-claude-spawner-token -n n8n-system \
  -o jsonpath='{.data.ca\.crt}')
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Build kubeconfig
cat <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: cluster
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA}
contexts:
  - name: spawner
    context:
      cluster: cluster
      user: spawner
      namespace: claude-agents
current-context: spawner
users:
  - name: spawner
    user:
      token: ${TOKEN}
EOF
```

- [ ] **Step 5: Configure n8n Claude Code CLI credential**

In the n8n UI:

1. Go to Credentials → New Credential → Claude Code CLI (Kubernetes)
2. Auth method: Kubeconfig (inline)
3. Paste the kubeconfig from step 4
4. Namespace: `claude-agents`
5. Image: `ghcr.io/anthony-spruyt/claude-agent:<tag>@<digest>`
6. Service account: `claude-agent`
7. Memory limit: `2Gi`
8. CPU limit: `1`
9. Save

- [ ] **Step 6: Create and run PoC workflow**

In n8n UI:

1. Create new workflow "Claude Code PoC"
2. Add Manual Trigger node
3. Add Claude Code CLI node:
   - Credential: select the one created in step 5
   - Prompt: "List the Kubernetes namespaces available via MCP and query
     a VictoriaMetrics metric. Report what you find."
   - Max turns: 5
   - Max budget: $1.00
4. Execute workflow
5. **While the pod is running**, check its labels:
   `kubectl get pod -n claude-agents --show-labels`
   Verify the pod has `app.kubernetes.io/name: claude-agent` (or similar).
   **If the community node does NOT apply this label**, all CNPs are
   no-ops. Fix by either: (a) configuring labels in the community node's
   credential settings, (b) using a Kyverno mutating policy, or
   (c) updating CNP selectors to match the actual pod labels.
6. Verify:
   - Pod appears in `claude-agents` namespace
   - Workflow completes successfully
   - Output contains namespace list and metric data
   - Pod is deleted after completion

- [ ] **Step 7: Test Discord channels (if bot token is available)**

If the Discord bot token is ready, re-run with
`--channels plugin:discord@claude-plugins-official` and `DISCORD_BOT_TOKEN`
in the community node's `envVars` field. Verify Claude posts to Discord.
If not ready, defer to phase 2.
