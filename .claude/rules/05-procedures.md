# Procedures

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

## Stuck HelmRelease Recovery

> **Flux suspend/resume does NOT unstick a failed HelmRelease.** Do not attempt it.

**Existing release with good prior revision:**
```bash
helm rollback <release> <revision> -n <namespace>
```

**New release with no good revision (first install failed):**

> **NEVER delete kustomizations for stateful/critical infrastructure (rook-ceph, volsync, cnpg, flux-system). Ask user first if unsure.**

```bash
flux delete kustomization <name> -n flux-system
# Flux will recreate it on next reconciliation
```
