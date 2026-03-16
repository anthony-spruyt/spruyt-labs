# VPA Deployment Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy VPA to enable automated resource right-sizing, replacing the manual quarterly resource review process.

**Architecture:** Single HelmRelease in dedicated `vpa-system` namespace deploying all three VPA components (recommender, updater, admission-controller) with `updateMode: "Off"`. CiliumNetworkPolicies lock down traffic to API server egress, webhook ingress, and metrics scraping.

**Tech Stack:** Cowboysysop Helm chart, FluxCD, Cilium CNPs, Kustomize ConfigMapGenerator

**Spec:** `docs/superpowers/specs/2026-03-16-vpa-deployment-design.md`
**Issue:** [#674](https://github.com/anthony-spruyt/spruyt-labs/issues/674)

---

## File Structure

### New Files

| File | Purpose |
|------|---------|
| `cluster/apps/vpa-system/namespace.yaml` | Namespace with PSA + descheduler labels |
| `cluster/apps/vpa-system/kustomization.yaml` | Top-level kustomization referencing namespace + ks.yaml |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/ks.yaml` | Flux Kustomization targeting `./app` |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/README.md` | Component documentation |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomization.yaml` | ConfigMapGenerator + resources |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/app/release.yaml` | HelmRelease for cowboysysop chart |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml` | Helm values (resources, priority, security) |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomizeconfig.yaml` | ConfigMap hash reference injection |
| `cluster/apps/vpa-system/vertical-pod-autoscaler/app/network-policies.yaml` | CNPs: API egress, webhook ingress, metrics ingress |
| `cluster/flux/meta/repositories/helm/cowboysysop-charts.yaml` | HelmRepository for cowboysysop |

### Modified Files

| File | Change |
|------|--------|
| `cluster/apps/kustomization.yaml` | Add `./vpa-system` entry |
| `cluster/flux/meta/repositories/helm/kustomization.yaml` | Add `./cowboysysop-charts.yaml` entry |
| `cluster/apps/kube-system/descheduler/app/values.yaml` | Add `vpa-system` to per-plugin exclusion lists |
| `cluster/apps/spegel/spegel/app/values.yaml` | Set VPA updatePolicy to `"Off"` |

### Deleted Files

| File | Reason |
|------|--------|
| `.claude/prompts/quarterly-resource-review.md` | Replaced by VPA automated recommendations |

### Bulk Edits

~103 resource-sizing comments stripped across ~53 files under `cluster/apps/`.

---

## Chunk 1: VPA Deployment

### Task 1: Add HelmRepository

**Files:**
- Create: `cluster/flux/meta/repositories/helm/cowboysysop-charts.yaml`
- Modify: `cluster/flux/meta/repositories/helm/kustomization.yaml`

- [ ] **Step 1: Create cowboysysop HelmRepository**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: cowboysysop-charts
  namespace: flux-system
spec:
  url: https://cowboysysop.github.io/charts
```

- [ ] **Step 2: Add to helm repo kustomization**

Add `./cowboysysop-charts.yaml` to `cluster/flux/meta/repositories/helm/kustomization.yaml` resources list. Insert after `./cilium-charts.yaml` and before `./descheduler-charts.yaml`.

- [ ] **Step 3: Commit**

```bash
git add cluster/flux/meta/repositories/helm/cowboysysop-charts.yaml cluster/flux/meta/repositories/helm/kustomization.yaml
git commit -m "feat(vpa): add cowboysysop HelmRepository

Ref #674"
```

---

### Task 2: Create namespace and top-level kustomization

**Files:**
- Create: `cluster/apps/vpa-system/namespace.yaml`
- Create: `cluster/apps/vpa-system/kustomization.yaml`
- Modify: `cluster/apps/kustomization.yaml`

- [ ] **Step 1: Create namespace**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: vpa-system
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 2: Create top-level kustomization**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./vertical-pod-autoscaler/ks.yaml
```

- [ ] **Step 3: Add vpa-system to cluster/apps/kustomization.yaml**

Add `- ./vpa-system` to the resources list. Insert alphabetically — after `./velero` and before the commented-out entries.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/vpa-system/namespace.yaml cluster/apps/vpa-system/kustomization.yaml cluster/apps/kustomization.yaml
git commit -m "feat(vpa): create vpa-system namespace

Ref #674"
```

---

### Task 3: Create Flux Kustomization

**Files:**
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/ks.yaml`

- [ ] **Step 1: Create ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app vertical-pod-autoscaler
  namespace: flux-system
spec:
  targetNamespace: vpa-system
  path: "./cluster/apps/vpa-system/vertical-pod-autoscaler/app"
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  prune: true
  timeout: 5m
  wait: true  # Ensures VPA CRDs are registered before dependents (e.g., Spegel) reconcile
```

> **Note:** `wait: true` deviates from the kubelet-csr-approver reference pattern. This is intentional — VPA installs CRDs that other workloads depend on (Spegel creates VPA objects). Without `wait`, Flux might reconcile Spegel before VPA CRDs exist.

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/vpa-system/vertical-pod-autoscaler/ks.yaml
git commit -m "feat(vpa): add Flux Kustomization

Ref #674"
```

---

### Task 4: Create HelmRelease, values, kustomize config, and network policies

**Files:**
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/release.yaml`
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml`
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomizeconfig.yaml`
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomization.yaml`
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/network-policies.yaml`

> **Note:** kustomization.yaml references network-policies.yaml, so both must exist in the same commit to avoid transient Flux failures.

- [ ] **Step 1: Create release.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: vertical-pod-autoscaler
spec:
  chart:
    spec:
      chart: vertical-pod-autoscaler
      version: 11.1.1
      sourceRef:
        kind: HelmRepository
        name: cowboysysop-charts
        namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: vertical-pod-autoscaler-values
```

- [ ] **Step 2: Create values.yaml**

```yaml
# Default values for vertical-pod-autoscaler
# Chart: https://github.com/cowboysysop/charts/tree/master/charts/vertical-pod-autoscaler

admissionController:
  priorityClassName: high-priority
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      memory: 512Mi

recommender:
  priorityClassName: high-priority
  resources:
    requests:
      cpu: 50m
      memory: 512Mi
    limits:
      memory: 1024Mi

updater:
  priorityClassName: high-priority
  resources:
    requests:
      cpu: 50m
      memory: 512Mi
    limits:
      memory: 1024Mi
```

- [ ] **Step 3: Create kustomizeconfig.yaml**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

- [ ] **Step 4: Create app kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
  - ./network-policies.yaml
configMapGenerator:
  - name: vertical-pod-autoscaler-values
    namespace: vpa-system
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 5: Create network-policies.yaml**

Reference patterns:
- API egress: `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/network-policies.yaml`
- Webhook ingress: `cluster/apps/kyverno/kyverno/app/network-policies.yaml` (allow-webhook-ingress)
- Metrics ingress: `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/network-policies.yaml` (allow-metrics-ingress)

The VPA chart uses these labels on its pods:
- `app.kubernetes.io/name: vertical-pod-autoscaler`
- `app.kubernetes.io/component: admission-controller|recommender|updater`

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# All VPA components need kube-apiserver access to read metrics and write recommendations
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vertical-pod-autoscaler
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Webhook ingress for admission-controller
# kube-apiserver calls the mutating webhook on port 8000
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-webhook-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vertical-pod-autoscaler
      app.kubernetes.io/component: admission-controller
  ingress:
    - fromEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Metrics ingress from vmagent for all components
# Ports: recommender=8942, updater=8943, admission-controller=8944
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-metrics-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: vertical-pod-autoscaler
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "8942"
              protocol: TCP
            - port: "8943"
              protocol: TCP
            - port: "8944"
              protocol: TCP
```

- [ ] **Step 6: Verify pod labels match chart output**

Before committing, verify the chart actually uses these labels by checking chart templates:

```bash
# Fetch and inspect chart templates for label patterns
helm template vpa cowboysysop/vertical-pod-autoscaler --version 11.1.1 2>/dev/null | grep -A5 "app.kubernetes.io" | head -30
```

If labels differ, update the CNP selectors to match.

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/vpa-system/vertical-pod-autoscaler/app/release.yaml cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomizeconfig.yaml cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomization.yaml cluster/apps/vpa-system/vertical-pod-autoscaler/app/network-policies.yaml
git commit -m "feat(vpa): add HelmRelease, values, and CiliumNetworkPolicies

Ref #674"
```

---

### Task 5: Add descheduler namespace exclusion

**Files:**
- Modify: `cluster/apps/kube-system/descheduler/app/values.yaml`

- [ ] **Step 1: Add vpa-system to all per-plugin exclusion lists**

In `cluster/apps/kube-system/descheduler/app/values.yaml`, add `- vpa-system` to the `exclude` list in each plugin's `namespaces` (or `evictableNamespaces` for LowNodeUtilization). There are 5 plugins with exclusion lists:

1. `RemoveDuplicates` → `namespaces.exclude`
2. `RemovePodsViolatingTopologySpreadConstraint` → `namespaces.exclude`
3. `RemoveFailedPods` → `namespaces.exclude`
4. `RemovePodsHavingTooManyRestarts` → `namespaces.exclude`
5. `LowNodeUtilization` → `evictableNamespaces.exclude`

Insert at the end of each list — after `- cloudflare-system` (currently the last entry in each list).

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kube-system/descheduler/app/values.yaml
git commit -m "feat(vpa): add vpa-system to descheduler exclusion lists

Ref #674"
```

---

### Task 6: Set Spegel VPA updateMode to Off

**Files:**
- Modify: `cluster/apps/spegel/spegel/app/values.yaml`

> **Important:** `updateMode` is configured per VPA object (CRD), not at the chart/controller level. The VPA controllers deployed in Task 4 have no global mode setting. Spegel's chart creates a VPA object with `updateMode: Auto` by default — we must override to `"Off"`.

- [ ] **Step 1: Add updatePolicy to Spegel's VPA config**

In `cluster/apps/spegel/spegel/app/values.yaml`, update the `verticalPodAutoscaler` block to include `updatePolicy`:

```yaml
verticalPodAutoscaler:
  updatePolicy:
    updateMode: "Off"
  maxAllowed:
    cpu: 10m
    memory: 128Mi
  minAllowed:
    cpu: 2m
    memory: 24Mi
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/spegel/spegel/app/values.yaml
git commit -m "feat(vpa): set Spegel VPA updateMode to Off

Recommendation-only mode until VPA recommendations are validated.

Ref #674"
```

---

### Task 7: Create README

**Files:**
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/README.md`

- [ ] **Step 1: Create README following template**

Use `docs/templates/readme_template.md` as base. Key details:

- Component: Vertical Pod Autoscaler
- Namespace: vpa-system
- Priority: high-priority
- No dependsOn
- Components: recommender, updater, admission-controller
- Update mode: Off (recommendation-only)
- Key commands: `kubectl describe vpa -A` to view recommendations

```markdown
# Vertical Pod Autoscaler - Automated Resource Right-Sizing

## Overview

VPA automatically recommends resource requests and limits for workloads based on actual usage metrics. Deployed with `updateMode: "Off"` — generates recommendations only, does not modify pods. Priority tier: `high-priority`.

Components:
- **Recommender**: Watches all workloads, generates resource recommendations
- **Updater**: Evicts pods needing updates (inactive with `updateMode: "Off"`)
- **Admission Controller**: Mutating webhook that sets resources on pod creation (inactive with `updateMode: "Off"`)

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the vpa-system namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n vpa-system
flux get helmrelease -n flux-system vertical-pod-autoscaler

# View VPA recommendations for all workloads
kubectl describe vpa -A

# Force reconcile
flux reconcile kustomization vertical-pod-autoscaler --with-source

# View logs
kubectl logs -n vpa-system -l app.kubernetes.io/name=vertical-pod-autoscaler
```

### Enabling Auto-Updates

To enable VPA auto-updates for a specific workload, create a `VerticalPodAutoscaler` resource with `updateMode: "Auto"` targeting that workload. Start with low-risk, stateless workloads.

## Troubleshooting

### Common Issues

1. **VPA recommendations not appearing**
   - **Symptom**: `kubectl describe vpa` shows no recommendations
   - **Resolution**: Recommender needs ~24h of metrics data. Check recommender logs for errors.

2. **Webhook failures after enabling Auto mode**
   - **Symptom**: Pods fail to create with admission webhook errors
   - **Resolution**: Check admission-controller pod health and CNP allows webhook ingress from API server on port 8000.

## References

- [Kubernetes VPA Documentation](https://kubernetes.io/docs/concepts/workloads/autoscaling/)
- [Cowboysysop Chart](https://github.com/cowboysysop/charts/tree/master/charts/vertical-pod-autoscaler)
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/vpa-system/vertical-pod-autoscaler/README.md
git commit -m "docs(vpa): add README

Ref #674"
```

---

### Task 8: Run qa-validator

- [ ] **Step 1: Run qa-validator agent**

Run the qa-validator agent to validate all changes before pushing.

- [ ] **Step 2: Fix any issues found**

If qa-validator reports issues, fix them and re-run until approved.

---

## Chunk 2: Cleanup

### Task 9: Delete quarterly resource review prompt

**Files:**
- Delete: `.claude/prompts/quarterly-resource-review.md`

- [ ] **Step 1: Delete the file**

```bash
rm .claude/prompts/quarterly-resource-review.md
```

- [ ] **Step 2: Commit**

```bash
git add .claude/prompts/quarterly-resource-review.md
git commit -m "chore(vpa): remove quarterly-resource-review prompt

Replaced by VPA automated recommendations.

Ref #674"
```

---

### Task 10: Strip resource-sizing comments

**Files:**
- Modify: ~53 files under `cluster/apps/`

- [ ] **Step 1: Identify all resource-sizing comments**

Search for comments matching these patterns:
- `# P99 ...` (P99 metrics rationale)
- `# Critical infrastructure - no CPU limit...`
- `# high-priority - no CPU limit...`
- `# Tier ... / ... tier ...`
- `# Requests based on P99...`
- `# No CPU limit...`
- `# Increased requests to...`
- `# CPU is compressible...`
- `# +20% headroom...`

Use grep to build the full list:

```bash
grep -rn '# .*\(P99\|headroom\|CPU limit\|CPU is compressible\|tier.*resource\|Requests based on\|Increased requests\|resource requirements for\)' cluster/apps/ --include="*.yaml" | grep -v 'network-polic' | grep -v 'README'
```

- [ ] **Step 2: Strip comments**

For each file, remove the comment lines. Rules:
- Remove the entire comment line if it's a standalone line
- Remove trailing comments from the end of config lines
- Do NOT remove blank lines that result from comment removal if they separate logical sections
- Do NOT touch comments that explain non-sizing rationale (e.g., Ceph Thunderbolt network, SAML/SSL requirements)
- Do NOT touch `priorityClassName` values — those are functional config

- [ ] **Step 3: Verify no functional changes**

After stripping, run `kubectl kustomize` on a sample of affected directories to ensure YAML is still valid:

```bash
kubectl kustomize cluster/apps/velero/velero/app/ > /dev/null 2>&1 && echo "OK" || echo "FAIL"
kubectl kustomize cluster/apps/chrony/chrono/app/ > /dev/null 2>&1 && echo "OK" || echo "FAIL"
```

- [ ] **Step 4: Commit**

Stage only the specific files modified in Step 2. Do NOT use `git add -A`, `git add .`, or `git add -u` — multiple agents may have uncommitted work. Use the file list from Step 1's grep output to build explicit `git add` commands:

```bash
git add <file1> <file2> ... # explicit paths from grep output only
git commit -m "chore(vpa): strip manual resource-sizing comments

VPA automated recommendations replace manual P99-based sizing rationale.

Ref #674"
```

---

### Task 11: Run qa-validator on cleanup

- [ ] **Step 1: Run qa-validator agent**

Run qa-validator to verify cleanup changes pass linting.

- [ ] **Step 2: Fix any issues**

If issues found, fix and re-run.

---

### Task 12: Post-push validation

After user pushes to main:

- [ ] **Step 1: Run cluster-validator agent**

Verify Flux reconciles VPA successfully — all pods running, HelmRelease ready.

- [ ] **Step 2: Verify VPA components are running**

```bash
kubectl get pods -n vpa-system
kubectl get helmrelease -n flux-system vertical-pod-autoscaler
```

Expected: 3 pods running (recommender, updater, admission-controller).

- [ ] **Step 3: Verify VPA CRDs exist**

```bash
kubectl get crd | grep verticalpodautoscaler
```

Expected: `verticalpodautoscalers.autoscaling.k8s.io` and related CRDs.

- [ ] **Step 4: Verify Spegel VPA object was created**

```bash
kubectl get vpa -A
```

Expected: Spegel VPA object exists in spegel namespace.

- [ ] **Step 5: Check CNP is not blocking traffic**

```bash
# Check for policy drops in vpa-system
hubble observe -n vpa-system --verdict DROPPED --last 5m
```

Expected: No drops (or only expected default-deny drops before policies apply).
