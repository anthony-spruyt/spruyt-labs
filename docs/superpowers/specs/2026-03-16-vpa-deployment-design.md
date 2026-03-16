# VPA Deployment Design

**Issue:** [#674](https://github.com/anthony-spruyt/spruyt-labs/issues/674)
**Date:** 2026-03-16

## Overview

Deploy the Kubernetes Vertical Pod Autoscaler (VPA) to enable automated resource right-sizing across the cluster, replacing the manual quarterly resource review process.

## Decisions

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| Chart | `cowboysysop/vertical-pod-autoscaler` v11.1.1 | Actively maintained, recent VPA-specific releases |
| Namespace | `vpa-system` | Own namespace for clean isolation; VPA only needs API server access so CNPs are trivial |
| Components | Recommender + updater + admission-controller | Single HelmRelease, all three deployed |
| Update mode | `"Off"` globally | Recommendation-only to start; flip to `"Auto"` per-workload when confident |
| Recommender scope | All workloads cluster-wide | Automated right-sizing is the goal; `"Off"` mode means no risk |
| Pod Security | `baseline` (enforce), `restricted` (audit/warn) | Standard for cluster tools with no host access needs |
| Priority class | `high-priority` | Cluster infrastructure tooling, but not critical-path for cluster operation |

## Chart Source

- **Repository:** `https://cowboysysop.github.io/charts`
- **Chart:** `vertical-pod-autoscaler`
- **Version:** 11.1.1

## Namespace

`vpa-system` with labels:

```yaml
pod-security.kubernetes.io/enforce: baseline
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/warn: restricted
descheduler.kubernetes.io/exclude: "true"
```

Exclude from descheduler eviction — infrastructure controllers should not be disrupted. Also add `vpa-system` to the descheduler per-plugin exclusion lists in `cluster/apps/kube-system/descheduler/app/values.yaml`.

## Network Policies

CiliumNetworkPolicy for `vpa-system`:

**Egress:**
- API server (port 6443) — all three components read metrics and write recommendations via the API

**Ingress:**
- Webhook from API server to admission-controller (port 8000) — mutating admission webhook; use `fromEntities: kube-apiserver` pattern (same as Kyverno/CNPG)
- Metrics scraping from VictoriaMetrics:
  - Recommender: port 8942
  - Updater: port 8943
  - Admission-controller: port 8944

DNS egress is handled by the cluster-wide `allow-kube-dns-egress` CiliumClusterwideNetworkPolicy in `cluster/flux/meta/cluster-network-policies.yaml`.

## Ports Reference

| Component | Container Port | Service Port | Purpose |
|-----------|---------------|--------------|---------|
| Admission-controller | 8000 | 443 | Webhook HTTPS |
| Admission-controller | 8944 | 8944 | Metrics |
| Recommender | 8942 | 8942 | Metrics |
| Updater | 8943 | 8943 | Metrics |

## File Structure

```
cluster/apps/vpa-system/
├── namespace.yaml
├── kustomization.yaml
└── vertical-pod-autoscaler/
    ├── ks.yaml
    ├── README.md
    └── app/
        ├── kustomization.yaml
        ├── release.yaml
        ├── values.yaml
        ├── kustomizeconfig.yaml
        └── network-policies.yaml

cluster/flux/meta/repositories/helm/
└── cowboysysop-charts.yaml
```

Updates to existing files:
- `cluster/apps/kustomization.yaml` — add `vpa-system` entry
- `cluster/flux/meta/repositories/helm/kustomization.yaml` — add cowboysysop repo

## Security Contexts

The chart defaults are already PSS-restricted compliant:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
podSecurityContext:
  seccompProfile:
    type: RuntimeDefault
```

No overrides needed — chart defaults match the repo's hardening standard.

## Initial Resource Requests

Based on chart-suggested defaults, to be refined by VPA's own recommendations:

| Component | CPU Request | Memory Request | CPU Limit | Memory Limit |
|-----------|------------|----------------|-----------|--------------|
| Admission-controller | 50m | 256Mi | - | 512Mi |
| Recommender | 50m | 512Mi | - | 1024Mi |
| Updater | 50m | 512Mi | - | 1024Mi |

No CPU limits — consistent with the repo's approach for infrastructure components.

## Dependencies

VPA has no dependencies — CRDs and controllers install independently. No `dependsOn` in `ks.yaml`. Use `wait: true` so CRDs are fully registered before other workloads reconcile.

Apps with native VPA support (Spegel) will create `VerticalPodAutoscaler` objects automatically on their next Flux reconciliation once the CRDs exist. No changes to Spegel needed.

## Spegel Integration

Spegel already has a VPA config block in its values:

```yaml
verticalPodAutoscaler:
  maxAllowed:
    cpu: 10m
    memory: 128Mi
  minAllowed:
    cpu: 2m
    memory: 24Mi
```

`minAllowed`/`maxAllowed` are recommendation clamps — VPA will not recommend below the floor or above the ceiling. These bounds should be reviewed once VPA generates real recommendation data.

## Cleanup

Cleanup should be a **separate commit** from the VPA deployment for clean git history and safer rollback.

### Delete

- `.claude/prompts/quarterly-resource-review.md` — replaced by VPA automated recommendations

### Strip Resource-Sizing Comments

Remove ~103 resource-sizing comments across 53 files. These are comments that document manual P99-based sizing rationale, which VPA automates. Patterns include:

- `# P99 42m total (3 replicas) - no CPU limit, +20% headroom`
- `# Critical infrastructure - no CPU limit (CPU is compressible)`
- `# standard tier - lower resource requirements for...`
- `# Requests based on P99: 29m CPU, +20% headroom`
- `# high-priority - no CPU limit; P99 310m, request set to P99+20%`

### Keep

- `docs/workload-classification.md` — documents priority class scheduling, independent of resource sizing
- Priority class assignments in values files — functional config, not sizing comments
- Comments explaining resource settings for non-sizing reasons (e.g., Ceph OSD burst at startup)
