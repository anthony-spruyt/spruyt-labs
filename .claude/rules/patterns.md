---
paths: cluster/**
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
