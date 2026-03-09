# HelmRelease Defaults Kyverno Policy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move HelmRelease defaults from Flux Kustomization patches to a Kyverno ClusterPolicy with `+(anchor)` syntax so individual HelmReleases can override specific fields.

**Architecture:** A single Kyverno ClusterPolicy mutates all HelmReleases on CREATE/UPDATE, injecting defaults only for fields not already set. The existing Flux nested patch block is removed entirely.

**Tech Stack:** Kyverno ClusterPolicy, Flux Kustomization, Kustomize

---

### Task 1: Create GitHub issue

**Step 1: Create the issue**

Run:
```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(kyverno): move HelmRelease defaults to Kyverno policy" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Move HelmRelease default patches (timeout, interval, install, upgrade, rollback) from Flux Kustomization patches in `cluster/flux/cluster/ks.yaml` to a Kyverno ClusterPolicy using `+(anchor)` syntax.

## Motivation
Flux strategic merge patches always overwrite scalar fields, making it impossible for individual HelmReleases to override specific fields like `timeout` without opting out of all defaults. Kyverno's `+(field)` anchor syntax provides true "default if not set" semantics.

## Acceptance Criteria
- [ ] New ClusterPolicy `add-helmrelease-defaults` in `cluster/apps/kyverno/policies/app/`
- [ ] HelmRelease defaults removed from `cluster/flux/cluster/ks.yaml`
- [ ] Existing HelmReleases with custom `timeout` (openclaw, n8n, rook-ceph-cluster) retain their overrides
- [ ] `helmreleasedefaults.flux.home.arpa/disabled` label mechanism removed
- [ ] qa-validator passes

## Affected Area
- Apps (cluster/apps/)
- Flux/GitOps (cluster/flux/)
EOF
)"
```

**Step 2: Note the issue number for commits**

---

### Task 2: Revert unstaged changes

The working tree has unstaged changes from the earlier attempt. Revert them before starting clean.

**Files:**
- Revert: `cluster/apps/openclaw/openclaw/app/release.yaml`
- Revert: `cluster/flux/cluster/ks.yaml`

**Step 1: Revert unstaged changes**

Run:
```bash
git checkout -- cluster/apps/openclaw/openclaw/app/release.yaml cluster/flux/cluster/ks.yaml
```

**Step 2: Verify clean state**

Run:
```bash
git status
```

Expected: no modified files

---

### Task 3: Create the Kyverno ClusterPolicy

**Files:**
- Create: `cluster/apps/kyverno/policies/app/helmrelease-defaults.yaml`

**Step 1: Create the policy file**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kyverno.io/clusterpolicy_v1.json
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-helmrelease-defaults
  annotations:
    policies.kyverno.io/title: Add HelmRelease Defaults
    policies.kyverno.io/category: Flux Management
    policies.kyverno.io/severity: low
    policies.kyverno.io/subject: HelmRelease
    policies.kyverno.io/description: >-
      Injects default timeout, interval, install, upgrade, and rollback
      configuration into HelmReleases that don't already specify them.
      Individual HelmReleases can override any field by setting it explicitly.
spec:
  background: false
  rules:
    - name: add-helmrelease-defaults
      match:
        any:
          - resources:
              kinds:
                - HelmRelease
              operations:
                - CREATE
                - UPDATE
      mutate:
        patchStrategicMerge:
          spec:
            +(timeout): 10m
            +(interval): 4h
            +(install):
              crds: CreateReplace
              strategy:
                name: RetryOnFailure
            +(rollback):
              cleanupOnFail: true
              recreate: true
            +(upgrade):
              cleanupOnFail: true
              crds: CreateReplace
              strategy:
                name: RemediateOnFailure
              remediation:
                remediateLastFailure: true
                retries: 2
```

---

### Task 4: Register policy in kustomization

**Files:**
- Modify: `cluster/apps/kyverno/policies/app/kustomization.yaml:5-8`

**Step 1: Add helmrelease-defaults.yaml to resources**

Change:
```yaml
resources:
  - ./default-limitrange.yaml
  - ./pss-restricted-defaults.yaml
  - ./topology-spread-policy.yaml
```

To:
```yaml
resources:
  - ./default-limitrange.yaml
  - ./helmrelease-defaults.yaml
  - ./pss-restricted-defaults.yaml
  - ./topology-spread-policy.yaml
```

---

### Task 5: Remove HelmRelease defaults from Flux ks.yaml

**Files:**
- Modify: `cluster/flux/cluster/ks.yaml:129-173`

**Step 1: Remove the entire HelmRelease defaults patch block**

Remove lines 129-173 (from `# Add defaults to all HelmRelease Kustomizations` comment through the `labelSelector: helmreleasedefaults...` line).

The file should end after line 128 (`labelSelector: substitution.flux.home.arpa/disabled notin (true)`), with only a trailing newline.

---

### Task 6: Add openclaw timeout override

The openclaw HelmRelease needs `timeout: 15m` set explicitly so Kyverno's `+(timeout): 10m` default is skipped.

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/release.yaml`

**Step 1: Add timeout to openclaw release**

Current (committed):
```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  valuesFrom:
```

Change to:
```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  timeout: 15m
  valuesFrom:
```

---

### Task 7: Run qa-validator

**Step 1: Run qa-validator agent**

Validate all modified files pass linting, schema validation, and dry-runs before committing.

---

### Task 8: Commit

**Step 1: Stage only modified files**

```bash
git add \
  cluster/apps/kyverno/policies/app/helmrelease-defaults.yaml \
  cluster/apps/kyverno/policies/app/kustomization.yaml \
  cluster/flux/cluster/ks.yaml \
  cluster/apps/openclaw/openclaw/app/release.yaml
```

**Step 2: Commit**

```bash
git commit -m "feat(kyverno): move HelmRelease defaults to Kyverno policy

Move timeout, interval, install, upgrade, and rollback defaults from
Flux Kustomization patches to a Kyverno ClusterPolicy using +(anchor)
syntax. This allows individual HelmReleases to override specific fields
without opting out of all defaults.

Ref #<issue-number>"
```

---

### Task 9: Post-push cluster validation

After user pushes to main, run cluster-validator to verify:
- Kyverno policy is applied
- HelmReleases have correct defaults
- openclaw/n8n/rook-ceph-cluster retain their 15m timeout overrides
