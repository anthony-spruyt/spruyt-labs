# Procedures

Common operational patterns for the homelab.

## Flux Operations

```bash
# Reconcile kustomization
flux reconcile kustomization <name> --with-source

# Check status
flux get kustomizations -n flux-system
flux get helmreleases -n <namespace>

# Diff before apply
flux diff ks <name> --path=./path
flux diff hr <name> --namespace <namespace>
```

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

## Error Recovery

```bash
# RBAC issues (prefer MCP: mcp__kubectl__audit_rbac_permissions)
kubectl auth can-i <verb> <resource>

# Flux rollback
flux suspend kustomization <name>
# (revert commit)
flux reconcile kustomization <name> --with-source

# Helm rollback (stuck helm release and flux reconcillations because of previous failed/failing helm release)
helm rollback <release> <revision> -n <ns>
```
