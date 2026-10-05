---
paths: [cluster/**/*.yaml]
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

Check the chart's upstream `values.yaml` for the pinned chart version before editing Helm values (Context7, or WebFetch raw.githubusercontent.com) — key paths differ between charts and versions.

## VPA (Vertical Pod Autoscaler)

Every long-running workload (Deployment, StatefulSet, DaemonSet) must include a `vpa.yaml` in its `app/` directory.
Short-lived CronJobs/Jobs may skip it.

- `updateMode` = `Off` for Cilium, Rook Ceph, and the Victoria observability stack (a resize-on-restart there costs
  networking, storage quorum, or the telemetry you'd debug with); `Initial` for everything else
- Per-container `containerPolicies` (no wildcards)
- `controlledValues` = `RequestsOnly` — VPA adjusts requests only, never limits
- `minAllowed` = `cpu: 1m, memory: 1Mi` (unclamped for accurate recommendations)
- `maxAllowed` = current resource limits (omit CPU if no CPU limit is set)
- Containers with no resource specs: omit from `containerPolicies`
- `targetRef.name` must match the actual resource name in the cluster
- No `dependsOn: vertical-pod-autoscaler` needed — CRDs are seeded at bootstrap via Talos `extraManifests`, then updated by the `vertical-pod-autoscaler` chart's `crds/` directory
- Schema: `https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json`

If a recommendation hits a boundary, adjust `minAllowed`/`maxAllowed` and recheck.

## Descheduler Namespace Exclusion

To exclude a namespace from descheduler eviction, label it `descheduler.kubernetes.io/exclude: "true"` in its `namespace.yaml`. `DefaultEvictor.namespaceLabelSelector` skips any namespace carrying that label; no descheduler config change is needed.

Only core infrastructure namespaces should be excluded — workload namespaces rely on priority classes to control eviction order.

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

## Component Docs

READMEs are optional. If your change adds knowledge the manifests can't show (workaround, manual step, external
prerequisite, cross-component wiring, credential rotation), create or update the app's `README.md` in the same commit
using `docs/templates/readme_template.md`. See `.claude/rules/documentation.md`.

## Renovate Annotations

Inline `# renovate:` comments on non-Helm dependencies (images, GitHub releases). Search `cluster/` for existing examples before writing new ones.
