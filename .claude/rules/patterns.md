---
paths: [cluster/**]
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

When an app has optional resources that depend on it (e.g., ingress routes), add multiple Kustomizations in the same `ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
spec:
  path: ./cluster/apps/<namespace>/<app>/app
  ...
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp-ingress
spec:
  path: ./cluster/apps/<namespace>/<app>/ingress
  dependsOn:
    - name: myapp
    - name: other-dependency
  ...
```

## Variable Substitution

Available variables: `${EXTERNAL_DOMAIN}`, `${CLUSTER_ISSUER}`, `${TIMEZONE}`

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
- `minAllowed` = current resource requests
- `maxAllowed` = current resource limits (omit CPU if no CPU limit is set)
- Containers with no resource specs: omit from `containerPolicies`
- `targetRef.name` must match the actual resource name in the cluster
- No `dependsOn: vertical-pod-autoscaler` needed — CRDs are installed via Talos `extraManifests`
- Schema: `https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json`

If a recommendation hits a boundary, adjust `minAllowed`/`maxAllowed` and recheck.

## Descheduler Namespace Exclusion

To exclude a namespace from descheduler eviction:

1. Add the label to its `namespace.yaml`:

```yaml
metadata:
  labels:
    descheduler.kubernetes.io/exclude: "true"
```

2. Add the namespace to the per-plugin `namespaces.exclude` lists in `cluster/apps/kube-system/descheduler/app/values.yaml`.

> **Note:** Per-plugin exclusion lists are required due to an upstream bug in descheduler v0.35.1 where `namespaceLabelSelector` ignores `matchExpressions` when `matchLabels` is empty. The labels are maintained for future migration to `DefaultEvictor.namespaceLabelSelector` once the bug is fixed.
