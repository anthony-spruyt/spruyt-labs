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

## Ingress and Certificates

### Access Types

- **Internal (LAN)**: Use `.lan.${EXTERNAL_DOMAIN}` for local-only services
- **External**: Use `${EXTERNAL_DOMAIN}` for public access

### IngressRoute Pattern

Path: `cluster/apps/traefik/traefik/ingress/<workload>/ingress-routes.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: <workload>
  namespace: <namespace>
  annotations:
    external-dns.alpha.kubernetes.io/hostname: <workload>.${EXTERNAL_DOMAIN}
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`<workload>.${EXTERNAL_DOMAIN}`)
      kind: Rule
      services:
        - name: <service>
          port: <port>
  tls:
    secretName: <workload>-${EXTERNAL_DOMAIN/./-}-tls
```

Add to `cluster/apps/traefik/traefik/ingress/kustomization.yaml`.

### Certificate Pattern

Path: Same directory as IngressRoute

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: <workload>
  namespace: <namespace>
spec:
  secretName: <workload>-${EXTERNAL_DOMAIN/./-}-tls
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - <workload>.${EXTERNAL_DOMAIN}
```

### Validation

```bash
kubectl get ingressroute -A          # All routes
kubectl get certificates -A          # All certs (check Ready=True)
kubectl get secrets -A | grep tls    # TLS secrets
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
# RBAC issues
kubectl auth can-i <verb> <resource>

# Flux rollback
flux suspend kustomization <name>
# (revert commit)
flux reconcile kustomization <name> --with-source

# Helm rollback (stuck helm release and flux reconcillations because of previous failed/failing helm release)
helm rollback <release> <revision> -n <ns>
```
