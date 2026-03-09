# HelmRelease Defaults Kyverno Policy Implementation Plan (v2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move HelmRelease defaults from Flux Kustomization patches to a Kyverno ClusterPolicy for optional fields, and add `interval` explicitly to all HelmRelease manifests.

**Architecture:** Add `interval: 4h` to all 45 HelmRelease files (required CRD field). Create a Kyverno ClusterPolicy with `+(anchor)` syntax for optional defaults (timeout, install, upgrade, rollback). Remove the Flux nested patch block entirely.

**Tech Stack:** Kyverno ClusterPolicy, Flux Kustomization, Kustomize

---

### Task 1: Add `interval: 4h` to all HelmRelease files (batch 1 — files with `timeout` already set)

These 4 files already have `timeout:` in spec. Add `interval: 4h` adjacent to timeout.

**Files:**
- Modify: `cluster/apps/n8n-system/n8n/app/release.yaml`
- Modify: `cluster/apps/rook-ceph/rook-ceph-cluster/app/release.yaml`
- Modify: `cluster/apps/kube-system/cilium/app/release.yaml`
- Modify: `cluster/apps/openclaw/openclaw/app/release.yaml`

**Step 1: Add `interval` and `timeout` to each file**

For n8n (has `timeout: 15m` before `chartRef`):
```yaml
spec:
  interval: 4h
  timeout: 15m
  chartRef:
```

For rook-ceph-cluster (has `timeout: 15m` before `chartRef`):
```yaml
spec:
  interval: 4h
  timeout: 15m
  chartRef:
```

For cilium (has `timeout: 2m` after `chart` block):
```yaml
spec:
  chart:
    ...
  interval: 4h
  timeout: 2m
  valuesFrom:
```

For openclaw (no timeout — add `interval` and `timeout: 15m` per design):
```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  interval: 4h
  timeout: 15m
  valuesFrom:
```

---

### Task 2: Add `interval: 4h` to all HelmRelease files (batch 2 — `chartRef` pattern, lines 6-7)

These files have `spec:` followed by `chartRef:` and no existing `interval` or `timeout`. Add `interval: 4h` after the `chartRef` block, before `valuesFrom` or next field.

**Files (14 files with `chartRef` and spec at line 6-7):**
- Modify: `cluster/apps/spegel/spegel/app/release.yaml`
- Modify: `cluster/apps/whoami/whoami/app/release.yaml`
- Modify: `cluster/apps/redisinsight/redisinsight/app/release.yaml`
- Modify: `cluster/apps/mosquitto/mosquitto/app/release.yaml`
- Modify: `cluster/apps/sungather/sungather/app/release.yaml`
- Modify: `cluster/apps/cloudflare-system/cloudflared/app/release.yaml`
- Modify: `cluster/apps/chrony/chrony/app/release.yaml`
- Modify: `cluster/apps/foundryvtt/foundryvtt/app/release.yaml`
- Modify: `cluster/apps/technitium/technitium-secondary/app/release.yaml`
- Modify: `cluster/apps/technitium/technitium/app/release.yaml`
- Modify: `cluster/apps/minecraft/bedrock-connect/app/release.yaml`
- Modify: `cluster/apps/vaultwarden/vaultwarden/app/release.yaml`
- Modify: `cluster/apps/kyverno/kyverno/app/release.yaml`
- Modify: `cluster/apps/minecraft/crafty-controller/app/release.yaml`

**Step 1: For each file, add `interval: 4h` after the `chartRef` block**

Pattern — find:
```yaml
    namespace: flux-system
  valuesFrom:
```

Replace with:
```yaml
    namespace: flux-system
  interval: 4h
  valuesFrom:
```

If file has no `valuesFrom`, add `interval: 4h` after the chartRef block's last line.

---

### Task 3: Add `interval: 4h` to all HelmRelease files (batch 3 — `chartRef` pattern, remaining)

**Files (7 files with `chartRef`):**
- Modify: `cluster/apps/observability/victoria-logs-single/app/release.yaml`
- Modify: `cluster/apps/observability/victoria-metrics-k8s-stack/app/release.yaml`
- Modify: `cluster/apps/observability/victoria-metrics-operator/app/release.yaml`
- Modify: `cluster/apps/rook-ceph/rook-ceph-operator/app/release.yaml`
- Modify: `cluster/apps/flux-system/flux-operator/app/release.yaml`
- Modify: `cluster/apps/flux-system/flux-instance/app/release.yaml`
- Modify: `cluster/apps/irq-balance/irq-balance-ms-01/app/release.yaml`

**Step 1: Same pattern as Task 2**

Find `namespace: flux-system` + next line, insert `interval: 4h` after chartRef block.

---

### Task 4: Add `interval: 4h` to all HelmRelease files (batch 4 — remaining `chartRef` pattern)

**Files (4 files):**
- Modify: `cluster/apps/irq-balance/irq-balance-e2/app/release.yaml`
- Modify: `cluster/apps/nut-system/nut-server/app/release.yaml`
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/release.yaml`
- Modify: `cluster/apps/firefly-iii/firemerge/app/release.yaml`

**Step 1: Same pattern as Task 2**

---

### Task 5: Add `interval: 4h` to all HelmRelease files (batch 5 — `chart:` spec pattern)

These files use inline `chart.spec` instead of `chartRef`. Add `interval: 4h` after the chart block.

**Files (16 files with `chart:` pattern):**
- Modify: `cluster/apps/external-dns/external-dns-technitium/app/release.yaml`
- Modify: `cluster/apps/firefly-iii/firefly-iii/app/release.yaml`
- Modify: `cluster/apps/valkey-system/valkey/app/release.yaml`
- Modify: `cluster/apps/cnpg-system/cnpg-operator/app/release.yaml`
- Modify: `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/release.yaml`
- Modify: `cluster/apps/headlamp-system/headlamp/app/release.yaml`
- Modify: `cluster/apps/cnpg-system/plugin-barman-cloud/app/release.yaml`
- Modify: `cluster/apps/qdrant-system/qdrant/app/release.yaml`
- Modify: `cluster/apps/kube-system/descheduler/app/release.yaml`
- Modify: `cluster/apps/velero/velero/app/release.yaml`
- Modify: `cluster/apps/falco-system/falco/app/release.yaml`
- Modify: `cluster/apps/external-secrets/external-secrets/app/release.yaml`
- Modify: `cluster/apps/cert-manager/cert-manager/app/release.yaml`
- Modify: `cluster/apps/authentik-system/authentik/app/release.yaml`
- Modify: `cluster/apps/reloader/reloader/app/release.yaml`
- Modify: `cluster/apps/traefik/traefik/app/release.yaml`

**Step 1: For each file, read and add `interval: 4h` after the chart block**

Pattern — find the end of the `chart.spec` block and insert `interval: 4h` before `valuesFrom:` or next field.

---

### Task 6: Create the Kyverno ClusterPolicy (optional fields only)

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
      Injects default timeout, install, upgrade, and rollback configuration
      into HelmReleases that don't already specify them. Individual
      HelmReleases can override any field by setting it explicitly.
      The interval field is set explicitly in each HelmRelease manifest.
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

Note: `+(interval)` is intentionally NOT included — it's a required CRD field that must be in the manifest.

---

### Task 7: Register policy in kustomization

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

### Task 8: Remove HelmRelease defaults from Flux ks.yaml

**Files:**
- Modify: `cluster/flux/cluster/ks.yaml:129-168`

**Step 1: Remove the entire HelmRelease defaults patch block**

Remove from `# Add defaults to all HelmRelease Kustomizations` through `labelSelector: helmreleasedefaults...` (lines 129-168).

The file should end after line 128 (`labelSelector: substitution.flux.home.arpa/disabled notin (true)`), with only a trailing newline.

---

### Task 9: Update README

**Files:**
- Modify: `cluster/apps/kyverno/policies/README.md`

**Step 1: Add documentation for the new policy**

Add a section for `add-helmrelease-defaults` after the `add-default-limitrange` section, before `## Operation`. Document:
- What it does (injects optional defaults via Kyverno)
- Table of defaults applied
- How to override (set field explicitly in HelmRelease spec)
- Note that `interval` is set explicitly in manifests, not via Kyverno

---

### Task 10: Run qa-validator

**Step 1: Run qa-validator agent**

Validate all 49 modified files pass linting, schema validation, and dry-runs before committing.

---

### Task 11: Commit

**Step 1: Stage only modified files**

```bash
git add \
  cluster/apps/kyverno/policies/app/helmrelease-defaults.yaml \
  cluster/apps/kyverno/policies/app/kustomization.yaml \
  cluster/apps/kyverno/policies/README.md \
  cluster/flux/cluster/ks.yaml \
  cluster/apps/*/*/app/release.yaml
```

IMPORTANT: Verify with `git status` that only expected files are staged. Do NOT use `git add -A`.

**Step 2: Commit**

```bash
git commit -m "feat(kyverno): move HelmRelease defaults to Kyverno policy

Add interval: 4h explicitly to all 45 HelmRelease manifests (required
CRD field). Move optional defaults (timeout, install, upgrade, rollback)
to a Kyverno ClusterPolicy using +(anchor) syntax for true default-if-
not-set semantics. Remove the Flux nested patch block.

Ref #616"
```

---

### Task 12: Post-push cluster validation

After user pushes to main, run cluster-validator to verify:
- All Flux kustomizations reconcile successfully
- Kyverno policy is applied and ready
- HelmReleases have correct defaults
- openclaw/n8n/rook-ceph-cluster retain their 15m timeout overrides
- cilium retains its 2m timeout override
