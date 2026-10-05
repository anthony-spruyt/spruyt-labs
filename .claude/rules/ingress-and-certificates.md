---
paths: [cluster/apps/traefik/**, cluster/apps/external-dns/**]
---

# Ingress and Certificates

## Access Types

- **Internal (LAN)**: Use `.lan.${EXTERNAL_DOMAIN}` for local-only services
- **External**: Use `${EXTERNAL_DOMAIN}` for public access

## IngressRoute Pattern

Path: `cluster/apps/traefik/traefik/ingress/<namespace>/`, holding `ingress-routes.yaml`, `certificates.yaml`, and `kustomization.yaml`. Copy `ingress/temporal-system/` as the reference.

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ingress-routes-lan-https # or ingress-routes-wan-https
  namespace: <namespace>
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    external-dns.kubernetes.io/hostname: <workload>.lan.${EXTERNAL_DOMAIN}
    external-dns.kubernetes.io/target: ${TRAEFIK_IP4}
spec:
  entryPoints: [websecure]
  routes:
    - kind: Rule
      match: Host(`<workload>.lan.${EXTERNAL_DOMAIN}`)
      middlewares:
        - name: lan-ip-whitelist
        - name: compress
      services:
        - name: <service>
          port: <port>
  tls:
    secretName: <workload>-lan-${EXTERNAL_DOMAIN/./-}-tls
```

LAN routes always carry the `lan-ip-whitelist` middleware. Middlewares come from `ingress/base/`: list each one used in the namespace `kustomization.yaml` and patch its `metadata.namespace` to the target namespace, as the reference does.

List the route and certificate files in that directory's `kustomization.yaml`. A new directory also goes in `cluster/apps/traefik/traefik/ingress/kustomization.yaml`, and its app goes in `dependsOn` in `cluster/apps/traefik/traefik/ks.yaml`.

### DNS annotations

Both annotations are required for external-dns to create a record:

| Annotation                            | Why                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------- |
| `external-dns.kubernetes.io/hostname` | The name to create                                                     |
| `external-dns.kubernetes.io/target`   | IngressRoute status carries no LB IP, so the target cannot be inferred |

Without `target`, external-dns generates zero endpoints and logs `All records are already up to date` — no error. Check `external_dns_source_endpoints_total` to confirm it sees anything at all.

Use the `external-dns.kubernetes.io/` prefix. Keys are matched exactly with no fallback, so `external-dns.alpha.kubernetes.io/` annotations are silently ignored. Override the prefix with `--annotation-prefix` if it ever needs to change.

To opt a route out entirely, set `external-dns.kubernetes.io/controller: none` and drop the other two annotations — used for split-DNS names that resolve publicly via Cloudflare (`auth`). Any value other than `dns-controller` excludes the object at index time, before hostnames are read.

Omitting `target` is not an opt-out on its own: the traefik source also extracts hostnames from the `` Host(`...`) `` match rules, so the name is still picked up and only stays dormant for as long as no target exists.

external-dns manages A, AAAA and CNAME only. `HTTPS` (SVCB) records are outside its scope entirely and must be created by hand in Technitium alongside the A record.

## Certificate Pattern

Path: `certificates.yaml` next to the IngressRoute. `secretName` must match the route's `tls.secretName`.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "<workload>-lan-${EXTERNAL_DOMAIN/./-}"
  namespace: <namespace>
spec:
  secretName: "<workload>-lan-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - "<workload>.lan.${EXTERNAL_DOMAIN}"
```
