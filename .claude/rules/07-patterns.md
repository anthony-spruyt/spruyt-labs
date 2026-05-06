---
paths: [cluster/apps/**/ks.yaml, cluster/apps/**/kustomization.yaml, cluster/apps/**/release.yaml, cluster/apps/**/values.yaml, cluster/apps/**/vpa.yaml, cluster/apps/**/*.sops.yaml, cluster/apps/**/namespace.yaml]
---

# Cluster Patterns

## App Structure

```text
cluster/apps/<namespace>/
├── namespace.yaml          # Namespace with PSA labels
├── kustomization.yaml      # References namespace + app ks.yaml files
├── <app>/                  # Single app
│   ├── ks.yaml
│   ├── app/
│   │   ├── kustomization.yaml
│   │   ├── release.yaml        # HelmRelease
│   │   ├── values.yaml         # Helm values
│   │   ├── vpa.yaml            # VPA (recommendation-only)
│   │   └── *-secrets.sops.yaml # Encrypted secrets
│   └── <optional>/         # Optional dependent resources (e.g., ingress/)
├── <app1>/                 # Multiple apps (e.g., operator + instance)
│   ├── ks.yaml
│   └── app/
└── <app2>/
    ├── ks.yaml
    └── app/
```

## Multiple Kustomizations

When an app has optional dependent resources (e.g., ingress routes), add multiple Kustomizations in the same `ks.yaml` with `dependsOn`. See existing `ks.yaml` files in `cluster/apps/` for examples.

## Variable Substitution

Flux `postBuild.substituteFrom` injects variables into all Kustomizations via patches in `cluster/flux/cluster/ks.yaml`. Two sources:

- **`cluster-settings`** ConfigMap — `cluster/flux/meta/cluster-settings.yaml` (plaintext)
- **`cluster-secrets`** Secret — `cluster/flux/meta/cluster-secrets.sops.yaml` (SOPS-encrypted values, key names plaintext)

List available variables: `task flux:list-vars`

**Opt-out:** add label `substitution.flux.home.arpa/disabled: "true"` to a Kustomization.

## SOPS Naming

Pattern: `<name>-secrets.sops.yaml` or `<name>.sops.yaml`

## Helm Values

Before modifying Helm values, ALWAYS check upstream/source values.yaml first:

- Use Context7 or WebFetch with raw.githubusercontent.com to find correct key paths
- Never assume key names
- Verify the chart version matches when checking upstream docs

## VPA (Vertical Pod Autoscaler)

Every workload must include a `vpa.yaml` in its `app/` directory.

- `updateMode: "Off"` — recommendation-only
- Per-container `containerPolicies` (no wildcards)
- `minAllowed` = `cpu: 1m, memory: 1Mi` (unclamped for accurate recommendations)
- `maxAllowed` = current resource limits (omit CPU if no CPU limit is set)
- Containers with no resource specs: omit from `containerPolicies`
- `targetRef.name` must match the actual resource name in the cluster
- No `dependsOn: vertical-pod-autoscaler` needed — CRDs are installed via Talos `extraManifests`
- Schema: `https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json`

If a recommendation hits a boundary, adjust `minAllowed`/`maxAllowed` and recheck.

## Descheduler Namespace Exclusion

To exclude a namespace from descheduler eviction, add it to the per-plugin `namespaces.exclude` lists in `cluster/apps/kube-system/descheduler/app/values.yaml`.

Only core infrastructure namespaces should be excluded — workload namespaces rely on priority classes to control eviction order.

> **Upstream bug (descheduler v0.35.1):** `DefaultEvictor.namespaceLabelSelector` ignores `matchExpressions` when `matchLabels` is empty (`defaultevictor.go` guards with `len(MatchLabels) > 0`). The `descheduler.kubernetes.io/exclude` label is therefore inert. When upgrading descheduler, check if this is fixed — if so, switch from per-plugin `namespaces.exclude` lists to `DefaultEvictor.namespaceLabelSelector` with the label.

## HelmRelease with ConfigMapGenerator

When using `configMapGenerator` for HelmRelease values, add `kustomizeconfig.yaml` to handle the hash suffix:

```yaml
# kustomizeconfig.yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

```yaml
# kustomization.yaml
configMapGenerator:
  - name: <app>-values
    namespace: <namespace>
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

This transforms `valuesFrom.name: <app>-values` to `valuesFrom.name: <app>-values-<hash>` automatically.

## Renovate Annotations

Inline `# renovate:` comments on non-Helm dependencies (images, GitHub releases). Search `cluster/` for existing examples before writing new ones.
