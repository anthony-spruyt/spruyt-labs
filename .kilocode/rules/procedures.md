# Shared Procedures

## Purpose

Common operational patterns for spruyt-labs homelab. Prefer Taskfile automation over manual procedures.

## Flux Operations

### Basic Commands

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

## Ingress and Certificate Procedures

### Choosing Access Type

- **Internal (LAN)**: Use `.lan.${EXTERNAL_DOMAIN}` for local-only services
- **External**: Use `${EXTERNAL_DOMAIN}` for public access

### Creating IngressRoutes

1. Create `ingress-routes.yaml` in `cluster/apps/traefik/traefik/ingress/<workload>/`:

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

2. Add to `cluster/apps/traefik/traefik/ingress/kustomization.yaml`
3. Validate: `kubectl get ingressroute -n <namespace>`

For LAN access, use `.lan.${EXTERNAL_DOMAIN}` in hostname and match.

### Creating Certificates

1. Create `certificates.yaml` in same directory:

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

2. Add to kustomization.yaml
3. Validate: `kubectl get certificates -n <namespace>` (check Ready=True)

### Validation Commands

```bash
kubectl get ingressroute -A          # All routes
kubectl get certificates -A          # All certs
kubectl get secrets -A | grep tls    # TLS secrets
```

## MCP/Context7 Integration

Configuration is in `.kilocode/mcp.json`. The approved library catalog is in `.kilocode/context7-libraries.json`.

### Usage

1. Check catalog first: `grep -i '<topic>' .kilocode/context7-libraries.json`
2. Use `resolve-library-id` if topic not in catalog
3. Use `get-library-docs` to retrieve documentation
4. Record library ID and version in change notes

### Example

```bash
use_mcp_tool server_name=context7 tool_name=resolve-library-id arguments={"description": "Kubernetes Ingress API"}
use_mcp_tool server_name=context7 tool_name=get-library-docs arguments={"library_id": "kubernetes", "version": "v1.28"}
```

## Validation

### Procedure Validation Steps

1. Execute commands in sequence
2. Verify outputs match expectations
3. Confirm functionality achieved
4. Document any issues

### Expected Outcomes

- Commands execute without errors
- Resources created/modified correctly
- Services available and functional
- Cluster remains stable

## Related

- [core_rules.md](core_rules.md) - Operational constraints
- [documentation_rules.md](documentation_rules.md) - Documentation standards
