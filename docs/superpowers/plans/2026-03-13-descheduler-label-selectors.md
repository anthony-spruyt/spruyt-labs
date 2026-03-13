# Descheduler Label Selectors Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded namespace exclusion lists in descheduler with a single label-based selector on DefaultEvictor.

**Architecture:** Label 6 namespaces with `descheduler.kubernetes.io/exclude: "true"`, configure DefaultEvictor's `namespaceLabelSelector` with `DoesNotExist` to filter globally, remove all per-plugin exclusion lists.

**Tech Stack:** Kubernetes namespaces, Flux Kustomize, descheduler Helm chart v0.35.1

**Spec:** `docs/superpowers/specs/2026-03-13-descheduler-label-selectors-design.md`
**Issue:** #641

---

## Chunk 1: Namespace Labeling

### Task 1: Add descheduler exclusion label to existing namespace manifests

**Files:**
- Modify: `cluster/apps/flux-system/namespace.yaml`
- Modify: `cluster/apps/rook-ceph/namespace.yaml`
- Modify: `cluster/apps/cloudflare-system/namespace.yaml`

- [ ] **Step 1: Add label to `flux-system/namespace.yaml`**

Add `descheduler.kubernetes.io/exclude: "true"` to the labels block:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: flux-system
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 2: Add label to `rook-ceph/namespace.yaml`**

Add `descheduler.kubernetes.io/exclude: "true"` to the labels block:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: rook-ceph
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    descheduler.kubernetes.io/exclude: "true"
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

- [ ] **Step 3: Add label to `cloudflare-system/namespace.yaml`**

Add `descheduler.kubernetes.io/exclude: "true"` to the labels block:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: cloudflare-system
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/flux-system/namespace.yaml cluster/apps/rook-ceph/namespace.yaml cluster/apps/cloudflare-system/namespace.yaml
git commit -m "feat(descheduler): add exclusion label to existing namespace manifests

Ref #641"
```

### Task 2: Create namespace manifest for kube-system

**Files:**
- Create: `cluster/apps/kube-system/namespace.yaml`
- Modify: `cluster/apps/kube-system/kustomization.yaml`

- [ ] **Step 1: Create `cluster/apps/kube-system/namespace.yaml`**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: kube-system
  labels:
    descheduler.kubernetes.io/exclude: "true"
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

- [ ] **Step 2: Add namespace.yaml to `cluster/apps/kube-system/kustomization.yaml`**

Add `./namespace.yaml` as the first resource entry. The file currently contains:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./cilium/ks.yaml
  - ./descheduler/ks.yaml
  - ./etcd-defrag/ks.yaml
  - ./hubble-sso/ks.yaml
  - ./snapshot-controller/ks.yaml
```

Change to:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./cilium/ks.yaml
  - ./descheduler/ks.yaml
  - ./etcd-defrag/ks.yaml
  - ./hubble-sso/ks.yaml
  - ./snapshot-controller/ks.yaml
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kube-system/namespace.yaml cluster/apps/kube-system/kustomization.yaml
git commit -m "feat(descheduler): create kube-system namespace manifest with exclusion label

Ref #641"
```

### Task 3: Create kube-public namespace directory and manifest

**Files:**
- Create: `cluster/apps/kube-public/namespace.yaml`
- Create: `cluster/apps/kube-public/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create directory**

```bash
mkdir -p cluster/apps/kube-public
```

- [ ] **Step 2: Create `cluster/apps/kube-public/namespace.yaml`**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: kube-public
  labels:
    descheduler.kubernetes.io/exclude: "true"
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

- [ ] **Step 3: Create `cluster/apps/kube-public/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
```

- [ ] **Step 4: Add to `cluster/apps/kustomization.yaml`**

Add `- ./kube-public` after the `- ./kube-system` entry (line 7). Keep alphabetical grouping of kube-* namespaces together.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/kube-public/namespace.yaml cluster/apps/kube-public/kustomization.yaml cluster/apps/kustomization.yaml
git commit -m "feat(descheduler): create kube-public namespace manifest with exclusion label

Ref #641"
```

### Task 4: Create kube-node-lease namespace directory and manifest

**Files:**
- Create: `cluster/apps/kube-node-lease/namespace.yaml`
- Create: `cluster/apps/kube-node-lease/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create directory**

```bash
mkdir -p cluster/apps/kube-node-lease
```

- [ ] **Step 2: Create `cluster/apps/kube-node-lease/namespace.yaml`**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: kube-node-lease
  labels:
    descheduler.kubernetes.io/exclude: "true"
  annotations:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

- [ ] **Step 3: Create `cluster/apps/kube-node-lease/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
```

- [ ] **Step 4: Add to `cluster/apps/kustomization.yaml`**

Add `- ./kube-node-lease` after `- ./kube-public` (or grouped with the other kube-* entries).

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/kube-node-lease/namespace.yaml cluster/apps/kube-node-lease/kustomization.yaml cluster/apps/kustomization.yaml
git commit -m "feat(descheduler): create kube-node-lease namespace manifest with exclusion label

Ref #641"
```

## Chunk 2: Descheduler Values and Documentation

### Task 5: Replace per-plugin exclusions with DefaultEvictor namespaceLabelSelector

**Files:**
- Modify: `cluster/apps/kube-system/descheduler/app/values.yaml`

- [ ] **Step 1: Replace the full `values.yaml` content**

Replace the entire `deschedulerPolicy` section. The file currently has 5 plugins each with their own `namespaces.exclude` or `evictableNamespaces.exclude` blocks (identical 6-namespace lists). Replace with:

```yaml
---
kind: CronJob
schedule: "*/30 * * * *"
timeZone: ${TIMEZONE}

priorityClassName: high-priority

resources:
  requests:
    cpu: 10m
    memory: 64Mi

# Namespace exclusion uses label selectors on DefaultEvictor instead of per-plugin lists.
# To exclude a namespace from descheduler eviction, add this label to its namespace.yaml:
#   descheduler.kubernetes.io/exclude: "true"

deschedulerPolicy:
  profiles:
    - name: default
      pluginConfig:
        - name: DefaultEvictor
          args:
            evictLocalStoragePods: false
            evictSystemCriticalPods: false
            evictFailedBarePods: true
            nodeFit: true
            namespaceLabelSelector:
              matchExpressions:
                - key: descheduler.kubernetes.io/exclude
                  operator: DoesNotExist
        - name: RemoveDuplicates
          args: {}
        - name: RemovePodsViolatingTopologySpreadConstraint
          args:
            constraints:
              - DoNotSchedule
        - name: RemoveFailedPods
          args:
            minPodLifetimeSeconds: 3600
        - name: RemovePodsHavingTooManyRestarts
          args:
            podRestartThreshold: 10
            includingInitContainers: true
        - name: LowNodeUtilization
          args:
            thresholds:
              cpu: 20
              memory: 20
            targetThresholds:
              cpu: 40
              memory: 40
      plugins:
        balance:
          enabled:
            - RemoveDuplicates
            - RemovePodsViolatingTopologySpreadConstraint
            - LowNodeUtilization
        deschedule:
          enabled:
            - RemoveFailedPods
            - RemovePodsHavingTooManyRestarts
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "feat(descheduler): replace per-plugin namespace exclusions with DefaultEvictor label selector

Ref #641"
```

### Task 6: Document label convention in patterns.md

**Files:**
- Modify: `.claude/rules/patterns.md`

- [ ] **Step 1: Add descheduler label convention section**

Append after the "Helm Values" section at the end of the file:

```markdown

## Descheduler Namespace Exclusion

To exclude a namespace from descheduler eviction, add this label to its `namespace.yaml`:

```yaml
labels:
  descheduler.kubernetes.io/exclude: "true"
```

The descheduler's `DefaultEvictor` uses a `namespaceLabelSelector` with `DoesNotExist` to skip labeled namespaces. No per-plugin configuration needed.
```

- [ ] **Step 2: Commit**

```bash
git add .claude/rules/patterns.md
git commit -m "docs(descheduler): add namespace exclusion label convention to patterns

Ref #641"
```

### Task 7: Validate and verify

- [ ] **Step 1: Run qa-validator**

Use the qa-validator agent to validate all changed files before pushing.

- [ ] **Step 2: Verify kustomize builds cleanly**

```bash
kubectl kustomize cluster/apps/kube-system/descheduler/app/
kubectl kustomize cluster/apps/kube-public/
kubectl kustomize cluster/apps/kube-node-lease/
kubectl kustomize cluster/apps/kube-system/
```

- [ ] **Step 3: Create PR**

```bash
gh pr create --title "feat(descheduler): switch namespace exclusions to label selectors" --body "$(cat <<'EOF'
## Summary
- Replace hardcoded namespace exclusion lists across 5 descheduler plugins with a single `namespaceLabelSelector` on `DefaultEvictor`
- Label 6 namespaces with `descheduler.kubernetes.io/exclude: "true"`
- Create namespace manifests for `kube-system`, `kube-public`, `kube-node-lease`

## Linked Issue
Closes #641

## Changes
- Add `descheduler.kubernetes.io/exclude: "true"` label to 6 namespace manifests
- Create `namespace.yaml` for `kube-system`, `kube-public`, `kube-node-lease` (with `prune: disabled`)
- Replace all per-plugin `namespaces.exclude` / `evictableNamespaces.exclude` with `DefaultEvictor.namespaceLabelSelector`
- Document label convention in `.claude/rules/patterns.md` and `values.yaml` comment

## Testing
- [ ] kustomize builds cleanly for all modified paths
- [ ] qa-validator passes
- [ ] After push: cluster-validator confirms Flux reconciliation
- [ ] Descheduler CronJob runs successfully
- [ ] Verify excluded namespaces are not evicted
EOF
)"
```
