# VictoriaMetrics MCP Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy the VictoriaMetrics MCP server in-cluster so Claude Code and OpenClaw can query metrics without port-forwarding.

**Architecture:** bjw-s app-template HelmRelease in `observability` namespace, exposed via LAN-only Traefik IngressRoute. OpenClaw connects via cluster DNS, Claude Code via HTTPS.

**Tech Stack:** bjw-s app-template, Traefik IngressRoute, cert-manager, CiliumNetworkPolicy, Flux

---

### Task 1: Create Flux Kustomization

**Files:**
- Create: `cluster/apps/observability/mcp-victoriametrics/ks.yaml`

**Step 1: Write ks.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app mcp-victoriametrics
  namespace: flux-system
spec:
  targetNamespace: observability
  path: ./cluster/apps/observability/mcp-victoriametrics/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: victoria-metrics-k8s-stack
  prune: true
  timeout: 5m
```

**Step 2: Verify**

Run: `kustomize build cluster/apps/observability/mcp-victoriametrics/ --load-restrictor=LoadRestrictionsNone 2>&1 | head -5`
Expected: Should not error (may warn about missing app/ dir until Task 2).

---

### Task 2: Create HelmRelease and Kustomize config

**Files:**
- Create: `cluster/apps/observability/mcp-victoriametrics/app/release.yaml`
- Create: `cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml`
- Create: `cluster/apps/observability/mcp-victoriametrics/app/kustomizeconfig.yaml`

**Step 1: Write release.yaml**

Reference pattern: `cluster/apps/redisinsight/redisinsight/app/release.yaml`

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: mcp-victoriametrics
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  valuesFrom:
    - kind: ConfigMap
      name: mcp-victoriametrics-values
```

**Step 2: Write kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
configMapGenerator:
  - name: mcp-victoriametrics-values
    namespace: observability
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

**Step 3: Write kustomizeconfig.yaml**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

---

### Task 3: Create bjw-s values.yaml

**Files:**
- Create: `cluster/apps/observability/mcp-victoriametrics/app/values.yaml`

**Step 1: Write values.yaml**

Reference pattern: `cluster/apps/redisinsight/redisinsight/app/values.yaml`
Image: `ghcr.io/victoriametrics-community/mcp-victoriametrics:v1.18.0@sha256:177f32eb91640b70a4ad2c246b7d27b4b2d0a530a423db7b3a6e4f2f9cb4d10f`

```yaml
---
# Default values: https://github.com/bjw-s-labs/helm-charts/blob/main/charts/library/common/values.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/tags/app-template-4.2.0/charts/library/common/values.schema.json
defaultPodOptions:
  priorityClassName: low-priority
  securityContext:
    runAsUser: 65534
    runAsGroup: 65534
    fsGroup: 65534
    fsGroupChangePolicy: "OnRootMismatch"
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
controllers:
  mcp-victoriametrics:
    strategy: Recreate
    containers:
      app:
        image:
          repository: ghcr.io/victoriametrics-community/mcp-victoriametrics
          tag: v1.18.0@sha256:177f32eb91640b70a4ad2c246b7d27b4b2d0a530a423db7b3a6e4f2f9cb4d10f
          pullPolicy: IfNotPresent
        env:
          - name: VM_INSTANCE_ENTRYPOINT
            value: "http://vmsingle-victoria-metrics-k8s-stack.observability.svc.cluster.local:8428"
          - name: VM_INSTANCE_TYPE
            value: "single"
          - name: MCP_SERVER_MODE
            value: "sse"
          - name: MCP_LISTEN_ADDR
            value: ":8080"
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 128Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        probes:
          liveness: &probes
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /health/liveness
                port: 8080
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
          readiness: *probes
service:
  app:
    controller: mcp-victoriametrics
    ports:
      http:
        port: 8080
```

Note: Uses `runAsUser: 65534` (nobody) since the Go binary doesn't need a specific user. Readiness probe reuses the liveness path — both `/health/liveness` and `/health/readiness` are available but liveness is sufficient for both since the server is stateless.

**Step 2: Validate kustomize build**

Run: `kustomize build cluster/apps/observability/mcp-victoriametrics/app --load-restrictor=LoadRestrictionsNone | head -30`
Expected: Valid YAML output with HelmRelease and ConfigMap.

---

### Task 4: Register in observability kustomization

**Files:**
- Modify: `cluster/apps/observability/kustomization.yaml`

**Step 1: Add resource reference**

Add `./mcp-victoriametrics/ks.yaml` to the resources list in `cluster/apps/observability/kustomization.yaml`:

```yaml
resources:
  - ./namespace.yaml
  - ./victoria-metrics-secret-writer/ks.yaml
  - ./victoria-metrics-operator/ks.yaml
  - ./victoria-metrics-k8s-stack/ks.yaml
  - ./victoria-logs-single/ks.yaml
  - ./mcp-victoriametrics/ks.yaml
```

**Step 2: Validate**

Run: `kustomize build cluster/apps/observability/ --load-restrictor=LoadRestrictionsNone | grep -A2 "name: mcp-victoriametrics"`
Expected: Shows the Kustomization resource.

---

### Task 5: Add Traefik IngressRoute and Certificate

**Files:**
- Modify: `cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml`
- Modify: `cluster/apps/traefik/traefik/ingress/observability/certificates.yaml`

**Step 1: Add IngressRoute**

Append to `cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml` (after the vmagent entry):

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/ingressroute_v1alpha1.json
# Documentation: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/ingressroute/
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ingress-routes-lan-https-mcp-vm
  namespace: observability
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    external-dns.alpha.kubernetes.io/hostname: mcp-vm.lan.${EXTERNAL_DOMAIN}
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`mcp-vm.lan.${EXTERNAL_DOMAIN}`)
      middlewares:
        - name: lan-ip-whitelist
        - name: compress
      services:
        - name: mcp-victoriametrics-app
          namespace: observability
          passHostHeader: true
          port: 8080
  tls:
    secretName: "mcp-vm-lan-${EXTERNAL_DOMAIN/./-}-tls"
```

Note: Service name `mcp-victoriametrics-app` follows bjw-s naming convention (`<release>-<service-name>`).

**Step 2: Add Certificate**

Append to `cluster/apps/traefik/traefik/ingress/observability/certificates.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "mcp-vm-lan-${EXTERNAL_DOMAIN/./-}"
  namespace: observability
spec:
  secretName: "mcp-vm-lan-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - "mcp-vm.lan.${EXTERNAL_DOMAIN}"
```

**Step 3: Validate**

Run: `kustomize build cluster/apps/traefik/traefik/ingress/observability/ --load-restrictor=LoadRestrictionsNone | grep "mcp-vm"`
Expected: Shows IngressRoute and Certificate resources with mcp-vm references.

---

### Task 6: Add OpenClaw egress CNP

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/network-policies.yaml`

**Step 1: Add egress policy**

Append after the `allow-n8n-egress` policy (after line 42) in `cluster/apps/openclaw/openclaw/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VictoriaMetrics MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-mcp-vm-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: openclaw
      app.kubernetes.io/name: openclaw
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: mcp-victoriametrics
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
```

---

### Task 7: Create README

**Files:**
- Create: `cluster/apps/observability/mcp-victoriametrics/README.md`

**Step 1: Write README**

Follow template from `docs/templates/readme_template.md`:

```markdown
# MCP VictoriaMetrics - MCP Server for VictoriaMetrics

## Overview

MCP (Model Context Protocol) server that provides AI assistants with access to VictoriaMetrics metrics data. Enables Claude Code and OpenClaw to query metrics, explore labels, analyze alerting rules, and debug queries without manual port-forwarding.

Deployed as a `low-priority` workload using bjw-s app-template.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- victoria-metrics-k8s-stack (metrics backend)

## Access

| Consumer | URL | Transport |
|----------|-----|-----------|
| Claude Code (dev container) | `https://mcp-vm.lan.${EXTERNAL_DOMAIN}/sse` | SSE over HTTPS (LAN-only) |
| OpenClaw (in-cluster) | `http://mcp-victoriametrics-app.observability.svc.cluster.local:8080/sse` | SSE over HTTP (cluster DNS) |
| Streamable HTTP | Same hosts, `/mcp` endpoint | HTTP (alternative transport) |

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n observability -l app.kubernetes.io/name=mcp-victoriametrics
flux get helmrelease -n flux-system mcp-victoriametrics

# Force reconcile (GitOps approach)
flux reconcile kustomization mcp-victoriametrics --with-source

# View logs
kubectl logs -n observability -l app.kubernetes.io/name=mcp-victoriametrics

# Test health
kubectl exec -it deploy/mcp-victoriametrics -n observability -- wget -qO- http://localhost:8080/health/readiness
```

## Troubleshooting

### Common Issues

1. **MCP server cannot reach VMSingle**
   - **Symptom**: Connection refused or timeout in logs
   - **Resolution**: Verify VMSingle is running: `kubectl get pods -n observability -l app.kubernetes.io/name=vmsingle`

2. **Claude Code cannot connect**
   - **Symptom**: MCP connection error in Claude Code
   - **Resolution**: Verify IngressRoute is active: `kubectl get ingressroute -n observability ingress-routes-lan-https-mcp-vm` and certificate is ready: `kubectl get certificate -n observability -l app.kubernetes.io/name=mcp-victoriametrics`

3. **OpenClaw cannot connect**
   - **Symptom**: MCP connection error in OpenClaw logs
   - **Resolution**: Verify CNP allows egress: `kubectl get cnp -n openclaw allow-mcp-vm-egress`

## References

- [VictoriaMetrics MCP Server](https://github.com/VictoriaMetrics/mcp-victoriametrics)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
```

---

### Task 8: Configure Claude Code MCP client

**Files:**
- Create: `.mcp.json`

**Step 1: Create .mcp.json**

The actual domain value must be hardcoded (no Flux substitution). Check `EXTERNAL_DOMAIN` from cluster settings:

Run: `grep -r "EXTERNAL_DOMAIN" cluster/flux/meta/ | grep -v sops | head -3`

Then create `.mcp.json` with the resolved domain:

```json
{
  "mcpServers": {
    "victoriametrics": {
      "type": "sse",
      "url": "https://mcp-vm.lan.<ACTUAL_DOMAIN>/sse"
    }
  }
}
```

Note: Ask the user for the actual domain value since `EXTERNAL_DOMAIN` comes from a ConfigMap that may reference SOPS secrets.

---

### Task 9: Run qa-validator and commit

**Step 1: Run qa-validator**

Use qa-validator agent to validate all changes before commit.

**Step 2: Commit**

```bash
git add cluster/apps/observability/mcp-victoriametrics/ks.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/release.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/kustomizeconfig.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/values.yaml \
  cluster/apps/observability/mcp-victoriametrics/README.md \
  cluster/apps/observability/kustomization.yaml \
  cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml \
  cluster/apps/traefik/traefik/ingress/observability/certificates.yaml \
  cluster/apps/openclaw/openclaw/app/network-policies.yaml \
  .mcp.json
git commit -m "feat(observability): add VictoriaMetrics MCP server

Deploy mcp-victoriametrics in-cluster for AI-assisted metrics queries.
Exposed via LAN-only Traefik IngressRoute with TLS.
OpenClaw egress CNP added for cluster-internal access.

Ref #<issue-number>"
```

---

### Task 10: Post-push validation and manual steps

**Step 1: User pushes to main**

**Step 2: Run cluster-validator**

Use cluster-validator agent to verify deployment.

**Step 3: Manual steps (user)**

1. Update OpenClaw `mcporter.json` SOPS secret to add:
   ```
   http://mcp-victoriametrics-app.observability.svc.cluster.local:8080/sse
   ```
2. Verify Claude Code MCP connection works by running a test query.
