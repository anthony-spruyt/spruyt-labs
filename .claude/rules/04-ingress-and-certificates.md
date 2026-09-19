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
    external-dns.kubernetes.io/hostname: <workload>.${EXTERNAL_DOMAIN}
    external-dns.kubernetes.io/target: ${TRAEFIK_IP4}
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

### DNS annotations

Both annotations are required for external-dns to create a record:

| Annotation                            | Why                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------- |
| `external-dns.kubernetes.io/hostname` | The name to create                                                     |
| `external-dns.kubernetes.io/target`   | IngressRoute status carries no LB IP, so the target cannot be inferred |

Without `target`, external-dns generates zero endpoints and logs `All records are already up to date` — no error. Check `external_dns_source_endpoints_total` to confirm it sees anything at all.

The `external-dns.alpha.kubernetes.io/` prefix is dead as of v0.22.0. Keys are matched exactly with no fallback, so `alpha` annotations are silently ignored. Override the prefix with `--annotation-prefix` if it ever needs to change.

To opt a route out entirely, set `external-dns.kubernetes.io/controller: none` and drop the other two annotations — used for split-DNS names that resolve publicly via Cloudflare (`auth`). Any value other than `dns-controller` excludes the object at index time, before hostnames are read.

Omitting `target` is not an opt-out on its own: the traefik source also extracts hostnames from the `` Host(`...`) `` match rules, so the name is still picked up and only stays dormant for as long as no target exists.

external-dns manages A, AAAA and CNAME only. `HTTPS` (SVCB) records are outside its scope entirely and must be created by hand in Technitium alongside the A record.

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
