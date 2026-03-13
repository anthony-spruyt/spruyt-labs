# Descheduler: Switch Namespace Exclusions to Label Selectors

**Issue:** #641
**Date:** 2026-03-13
**Status:** Approved

## Summary

Replace hardcoded namespace exclusion lists across 5 descheduler plugins with a single `namespaceLabelSelector` on the `DefaultEvictor` plugin, using the label `descheduler.kubernetes.io/exclude: "true"`.

## Motivation

All 5 descheduler plugins duplicate the same 6-namespace exclusion list (`kube-system`, `kube-public`, `kube-node-lease`, `flux-system`, `rook-ceph`, `cloudflare-system`). This creates maintenance burden and risk of forgetting to exclude critical namespaces when deploying new infrastructure.

## Approach

**Option A (selected): DefaultEvictor `namespaceLabelSelector` with `DoesNotExist`**

- Label excluded namespaces with `descheduler.kubernetes.io/exclude: "true"`
- Configure `DefaultEvictor` with a `namespaceLabelSelector` using `matchExpressions` with `DoesNotExist` operator
- Remove all per-plugin `namespaces.exclude` and `evictableNamespaces.exclude` blocks
- DefaultEvictor acts as a profile-wide gatekeeper — all plugins inherit the filtering

**Rejected alternatives:**
- **Opt-in model** (`Exists` operator): Would require labeling ~30 namespaces, silent failure mode when label is forgotten
- **Shared hardcoded lists**: Doesn't solve the duplication problem, doesn't auto-exclude new namespaces

## Design

### Part 1: Namespace Labeling

Add `descheduler.kubernetes.io/exclude: "true"` to 6 namespaces:

| Namespace | Action |
|---|---|
| `flux-system` | Add label to existing `namespace.yaml` |
| `rook-ceph` | Add label to existing `namespace.yaml` |
| `cloudflare-system` | Add label to existing `namespace.yaml` |
| `kube-system` | Create `namespace.yaml` in existing directory, add to `kustomization.yaml` |
| `kube-public` | Create new directory with `namespace.yaml` and `kustomization.yaml` |
| `kube-node-lease` | Create new directory with `namespace.yaml` and `kustomization.yaml` |

The 3 Kubernetes system namespaces get `kustomize.toolkit.fluxcd.io/prune: disabled` to prevent Flux from ever deleting them. Their existing labels were verified clean (only `kubernetes.io/metadata.name` which is auto-applied by Kubernetes).

New directories (`kube-public`, `kube-node-lease`) are added to `cluster/apps/kustomization.yaml`.

### Part 2: Descheduler Values

Replace all per-plugin namespace exclusions with a single `DefaultEvictor` config:

```yaml
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
```

All `namespaces.exclude` and `evictableNamespaces.exclude` blocks removed from individual plugins.

### Part 3: Documentation

Add label convention documentation to:
- **`values.yaml`**: Comment at the top explaining the label convention
- **`.claude/rules/patterns.md`**: Add convention so future Claude sessions apply it automatically

Convention: When deploying a namespace that should be excluded from descheduler eviction (infrastructure, storage, system-critical), add `descheduler.kubernetes.io/exclude: "true"` to its `namespace.yaml`.

## Files Changed

| File | Change |
|---|---|
| `cluster/apps/flux-system/namespace.yaml` | Add label |
| `cluster/apps/rook-ceph/namespace.yaml` | Add label |
| `cluster/apps/cloudflare-system/namespace.yaml` | Add label |
| `cluster/apps/kube-system/namespace.yaml` | **Create** with label + prune annotation |
| `cluster/apps/kube-system/kustomization.yaml` | Add `namespace.yaml` reference |
| `cluster/apps/kube-public/namespace.yaml` | **Create** with label + prune annotation |
| `cluster/apps/kube-public/kustomization.yaml` | **Create** referencing namespace.yaml |
| `cluster/apps/kube-node-lease/namespace.yaml` | **Create** with label + prune annotation |
| `cluster/apps/kube-node-lease/kustomization.yaml` | **Create** referencing namespace.yaml |
| `cluster/apps/kustomization.yaml` | Add `kube-public` and `kube-node-lease` |
| `cluster/apps/kube-system/descheduler/app/values.yaml` | Replace per-plugin exclusions with DefaultEvictor selector + add comment |
| `.claude/rules/patterns.md` | Add label convention |

## Verification

- Descheduler CronJob runs successfully after change
- Pods in excluded namespaces are not evicted
- Pods in non-excluded namespaces continue to be rebalanced
