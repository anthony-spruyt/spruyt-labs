---
paths: [cluster/apps/traefik/**]
---

# Ingress and Certificates

## Access Types

- **Internal (LAN)**: Use `.lan.${EXTERNAL_DOMAIN}` for local-only services
- **External**: Use `${EXTERNAL_DOMAIN}` for public access

## IngressRoute Pattern

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

## Certificate Pattern

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

## Validation

Prefer MCP tools: `mcp__kubectl__list_custom_resources` (IngressRoutes), `mcp__kubectl__list_certs` (Certificates).

Fallback:
```bash
kubectl get ingressroute -A          # All routes
kubectl get certificates -A          # All certs (check Ready=True)
```
