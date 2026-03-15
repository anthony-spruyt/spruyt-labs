# kubectl-mcp-server + MCP API Key Auth Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy kubectl-mcp-server in-cluster with Traefik ingress, API key auth on all MCP endpoints, and OpenClaw integration.

**Architecture:** kubectl-mcp-server runs in its own namespace with a read-only ClusterRole, exposed via Traefik with LAN-only access and API key authentication. The LinkPhoenix/traefik-api-key-auth Traefik plugin validates `X-API-KEY` headers using keys loaded from env vars. OpenClaw connects pod-to-pod (no Traefik).

**Tech Stack:** bjw-s app-template Helm chart, Traefik plugin (Go), CiliumNetworkPolicy, SOPS/Age, FluxCD

**Spec:** `docs/superpowers/specs/2026-03-15-kubectl-mcp-server-design.md`

---

## Chunk 1: kubectl-mcp-server App Deployment

### Task 1: Create namespace and namespace-level kustomization

**Files:**
- Create: `cluster/apps/kubectl-mcp/namespace.yaml`
- Create: `cluster/apps/kubectl-mcp/kustomization.yaml`

- [ ] **Step 1: Create namespace.yaml**

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: kubectl-mcp
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 2: Create namespace kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./kubectl-mcp-server/ks.yaml
```

- [ ] **Step 3: Register namespace in top-level kustomization**

Modify `cluster/apps/kustomization.yaml` — add `- ./kubectl-mcp` after `- ./openclaw` (end of active resources list).

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kubectl-mcp/namespace.yaml \
       cluster/apps/kubectl-mcp/kustomization.yaml \
       cluster/apps/kustomization.yaml
git commit -m "feat(kubectl-mcp): add namespace and kustomization"
```

### Task 2: Create RBAC resources

**Files:**
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/rbac.yaml`

- [ ] **Step 1: Create rbac.yaml with ServiceAccount, ClusterRole, ClusterRoleBinding**

```yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kubectl-mcp-server
  namespace: kubectl-mcp
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kubectl-mcp-server
rules:
  - apiGroups: [""]
    resources:
      - pods
      - services
      - configmaps
      - secrets
      - nodes
      - events
      - namespaces
      - persistentvolumes
      - persistentvolumeclaims
      - serviceaccounts
      - endpoints
      - resourcequotas
      - limitranges
      - replicationcontrollers
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources:
      - deployments
      - statefulsets
      - daemonsets
      - replicasets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["batch"]
    resources:
      - jobs
      - cronjobs
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources:
      - ingresses
      - networkpolicies
    verbs: ["get", "list", "watch"]
  - apiGroups: ["storage.k8s.io"]
    resources:
      - storageclasses
    verbs: ["get", "list", "watch"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources:
      - roles
      - rolebindings
      - clusterroles
      - clusterrolebindings
    verbs: ["get", "list", "watch"]
  - apiGroups: ["autoscaling"]
    resources:
      - horizontalpodautoscalers
    verbs: ["get", "list", "watch"]
  - apiGroups: ["policy"]
    resources:
      - poddisruptionbudgets
    verbs: ["get", "list", "watch"]
  - apiGroups: ["metrics.k8s.io"]
    resources:
      - nodes
      - pods
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubectl-mcp-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kubectl-mcp-server
subjects:
  - kind: ServiceAccount
    name: kubectl-mcp-server
    namespace: kubectl-mcp
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/app/rbac.yaml
git commit -m "feat(kubectl-mcp): add read-only RBAC for kubectl-mcp-server"
```

### Task 3: Create HelmRelease and values

**Files:**
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/ks.yaml`
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/release.yaml`
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/values.yaml`
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/kustomization.yaml`
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/kustomizeconfig.yaml`

- [ ] **Step 1: Create ks.yaml (Flux Kustomization)**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app kubectl-mcp-server
  namespace: flux-system
spec:
  targetNamespace: kubectl-mcp
  path: ./cluster/apps/kubectl-mcp/kubectl-mcp-server/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  prune: true
  timeout: 5m
```

- [ ] **Step 2: Create release.yaml (HelmRelease)**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: kubectl-mcp-server
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: kubectl-mcp-server-values
```

- [ ] **Step 3: Create values.yaml**

```yaml
---
# Default values: https://github.com/bjw-s-labs/helm-charts/blob/main/charts/library/common/values.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/refs/heads/main/charts/library/common/values.schema.json
defaultPodOptions:
  priorityClassName: low-priority
  automountServiceAccountToken: true
  securityContext:
    seccompProfile:
      type: RuntimeDefault
controllers:
  kubectl-mcp-server:
    strategy: Recreate
    containers:
      app:
        image:
          repository: docker.io/rohitghumare64/kubectl-mcp-server
          tag: latest@sha256:ad90bf2effc3926d22e8490c08f44299fb899b697214c957595c475841147439
          pullPolicy: IfNotPresent
        args:
          - "--transport"
          - "streamable-http"
        env:
          - name: KUBERNETES_SERVICE_HOST
            value: "kubernetes.default.svc.cluster.local"
          - name: MCP_DEBUG
            value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 512Mi
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /health
                port: 8000
              initialDelaySeconds: 10
              periodSeconds: 30
              timeoutSeconds: 3
              failureThreshold: 3
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /health
                port: 8000
              initialDelaySeconds: 5
              periodSeconds: 10
              timeoutSeconds: 3
              failureThreshold: 3
serviceAccount:
  name: kubectl-mcp-server
  create: false
service:
  app:
    controller: kubectl-mcp-server
    ports:
      http:
        port: 8000
```

- [ ] **Step 4: Create kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./release.yaml
  - ./rbac.yaml
  - ./network-policies.yaml
configMapGenerator:
  - name: kubectl-mcp-server-values
    namespace: kubectl-mcp
    files:
      - values.yaml
configurations:
  - ./kustomizeconfig.yaml
```

- [ ] **Step 5: Create kustomizeconfig.yaml**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/valuesFrom/name
        kind: HelmRelease
```

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/ks.yaml \
       cluster/apps/kubectl-mcp/kubectl-mcp-server/app/release.yaml \
       cluster/apps/kubectl-mcp/kubectl-mcp-server/app/values.yaml \
       cluster/apps/kubectl-mcp/kubectl-mcp-server/app/kustomization.yaml \
       cluster/apps/kubectl-mcp/kubectl-mcp-server/app/kustomizeconfig.yaml
git commit -m "feat(kubectl-mcp): add HelmRelease and values for kubectl-mcp-server"
```

### Task 4: Create CiliumNetworkPolicies for kubectl-mcp-server

**Files:**
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`

- [ ] **Step 1: Create network-policies.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Traefik
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-traefik-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubectl-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: traefik
            k8s:app.kubernetes.io/name: traefik
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from OpenClaw (pod-to-pod MCP access)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-openclaw-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubectl-mcp-server
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: openclaw
            k8s:app.kubernetes.io/instance: openclaw
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kube-apiserver
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-kube-api-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kubectl-mcp-server
  egress:
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml
git commit -m "feat(kubectl-mcp): add CiliumNetworkPolicies"
```

### Task 5: Create README

**Files:**
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/README.md`

- [ ] **Step 1: Create README using template**

```markdown
# kubectl-mcp-server - Kubernetes MCP Server

## Overview

MCP (Model Context Protocol) server providing AI assistants with read-only access to Kubernetes cluster resources. Deployed as a low-priority workload.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- No dependencies (self-contained with its own RBAC)

## Operation

### Key Commands

\`\`\`bash
# Check status
kubectl get pods -n kubectl-mcp
flux get helmrelease -n flux-system kubectl-mcp-server

# Force reconcile (GitOps approach)
flux reconcile kustomization kubectl-mcp-server --with-source

# View logs
kubectl logs -n kubectl-mcp -l app.kubernetes.io/name=kubectl-mcp-server
\`\`\`

## Troubleshooting

### Common Issues

1. **Pod fails to start**
   - **Symptom**: CrashLoopBackOff
   - **Resolution**: Check logs; likely ServiceAccount or RBAC issue. Verify ClusterRole and ClusterRoleBinding exist.

2. **MCP tools return 403 errors**
   - **Symptom**: Tool calls fail with permission denied
   - **Resolution**: Check ClusterRole has the required resource/verb. The ClusterRole is read-only by design.

## References

- [kubectl-mcp-server GitHub](https://github.com/rohitg00/kubectl-mcp-server)
- [bjw-s app-template](https://github.com/bjw-s-labs/helm-charts)
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/kubectl-mcp/kubectl-mcp-server/README.md
git commit -m "docs(kubectl-mcp): add README for kubectl-mcp-server"
```

## Chunk 2: Traefik Plugin and API Key Auth

### Task 6: Enable Traefik plugin and add env vars

**Files:**
- Modify: `cluster/apps/traefik/traefik/app/values.yaml`
- Modify: `cluster/apps/traefik/traefik/app/kustomization.yaml`

- [ ] **Step 1: Add experimental plugins and env vars to Traefik values**

Add to end of `cluster/apps/traefik/traefik/app/values.yaml`:

```yaml
experimental:
  plugins:
    traefik-api-key-auth:
      moduleName: "github.com/linkphoenix/traefik-api-key-auth"
      version: "v1.0.4"
env:
  - name: KUBECTL_MCP_API_KEY
    valueFrom:
      secretKeyRef:
        name: traefik-mcp-api-keys
        key: KUBECTL_MCP_API_KEY
  - name: VM_MCP_API_KEY
    valueFrom:
      secretKeyRef:
        name: traefik-mcp-api-keys
        key: VM_MCP_API_KEY
```

- [ ] **Step 2: Add SOPS secret placeholder to traefik app kustomization**

Modify `cluster/apps/traefik/traefik/app/kustomization.yaml` — add `- ./mcp-api-keys-secrets.sops.yaml` to resources list.

- [ ] **Step 3: Commit (without SOPS file — user creates that)**

```bash
git add cluster/apps/traefik/traefik/app/values.yaml \
       cluster/apps/traefik/traefik/app/kustomization.yaml
git commit -m "feat(traefik): enable API key auth plugin and env vars for MCP keys"
```

- [ ] **Step 4: User action — create SOPS secret**

**MANUAL STEP:** User creates `cluster/apps/traefik/traefik/app/mcp-api-keys-secrets.sops.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: traefik-mcp-api-keys
  namespace: traefik
stringData:
  KUBECTL_MCP_API_KEY: "<generated-key>"
  VM_MCP_API_KEY: "<generated-key>"
```

Then encrypts with: `sops --encrypt --in-place cluster/apps/traefik/traefik/app/mcp-api-keys-secrets.sops.yaml`

### Task 7: Create kubectl-mcp ingress (IngressRoute, Certificate, Middleware)

**Files:**
- Create: `cluster/apps/traefik/traefik/ingress/kubectl-mcp/kustomization.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/kubectl-mcp/ingress-routes.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/kubectl-mcp/certificates.yaml`
- Create: `cluster/apps/traefik/traefik/ingress/kubectl-mcp/api-key-auth.yaml`
- Modify: `cluster/apps/traefik/traefik/ingress/kustomization.yaml`
- Modify: `cluster/apps/traefik/traefik/ks.yaml` (add kubectl-mcp-server to dependsOn)

- [ ] **Step 1: Create api-key-auth.yaml middleware**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/middleware_v1alpha1.json
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: api-key-auth-kubectl-mcp
  namespace: kubectl-mcp
spec:
  plugin:
    traefik-api-key-auth:
      authenticationHeader: true
      authenticationHeaderName: X-API-KEY
      bearerHeader: false
      removeHeadersOnSuccess: true
      keys:
        - "env:KUBECTL_MCP_API_KEY"
```

- [ ] **Step 2: Create ingress-routes.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/ingressroute_v1alpha1.json
# Documentation: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/ingressroute/
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: ingress-routes-lan-https-kubectl-mcp
  namespace: kubectl-mcp
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    external-dns.alpha.kubernetes.io/hostname: kubectl-mcp.lan.${EXTERNAL_DOMAIN}
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`kubectl-mcp.lan.${EXTERNAL_DOMAIN}`)
      middlewares:
        - name: lan-ip-whitelist
        - name: api-key-auth-kubectl-mcp
      services:
        - name: kubectl-mcp-server
          namespace: kubectl-mcp
          passHostHeader: true
          port: 8000
  tls:
    secretName: "kubectl-mcp-lan-${EXTERNAL_DOMAIN/./-}-tls"
```

- [ ] **Step 3: Create certificates.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "kubectl-mcp-lan-${EXTERNAL_DOMAIN/./-}"
  namespace: kubectl-mcp
spec:
  secretName: "kubectl-mcp-lan-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - "kubectl-mcp.lan.${EXTERNAL_DOMAIN}"
```

- [ ] **Step 4: Create kustomization.yaml for ingress directory**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/lan-ip-whitelist.yaml
  - ./api-key-auth.yaml
  - ./certificates.yaml
  - ./ingress-routes.yaml
patches:
  - target:
      kind: Middleware
      name: lan-ip-whitelist
    patch: |
      - op: replace
        path: /metadata/namespace
        value: kubectl-mcp
```

- [ ] **Step 5: Register in ingress kustomization**

Modify `cluster/apps/traefik/traefik/ingress/kustomization.yaml` — add `- ./kubectl-mcp` to resources list.

- [ ] **Step 6: Add kubectl-mcp-server to traefik-ingress dependsOn**

Modify `cluster/apps/traefik/traefik/ks.yaml` — add `- name: kubectl-mcp-server` to the `traefik-ingress` Kustomization's `dependsOn` list.

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/traefik/traefik/ingress/kubectl-mcp/kustomization.yaml \
       cluster/apps/traefik/traefik/ingress/kubectl-mcp/ingress-routes.yaml \
       cluster/apps/traefik/traefik/ingress/kubectl-mcp/certificates.yaml \
       cluster/apps/traefik/traefik/ingress/kubectl-mcp/api-key-auth.yaml \
       cluster/apps/traefik/traefik/ingress/kustomization.yaml \
       cluster/apps/traefik/traefik/ks.yaml
git commit -m "feat(traefik): add kubectl-mcp ingress with API key auth"
```

### Task 8: Retrofit VM MCP with API key auth

**Files:**
- Create: `cluster/apps/traefik/traefik/ingress/observability/api-key-auth-vm-mcp.yaml`
- Modify: `cluster/apps/traefik/traefik/ingress/observability/kustomization.yaml`
- Modify: `cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml`

- [ ] **Step 1: Create api-key-auth-vm-mcp.yaml middleware**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/middleware_v1alpha1.json
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: api-key-auth-vm-mcp
  namespace: observability
spec:
  plugin:
    traefik-api-key-auth:
      authenticationHeader: true
      authenticationHeaderName: X-API-KEY
      bearerHeader: false
      removeHeadersOnSuccess: true
      keys:
        - "env:VM_MCP_API_KEY"
```

- [ ] **Step 2: Add to observability ingress kustomization**

Modify `cluster/apps/traefik/traefik/ingress/observability/kustomization.yaml` — add `- ./api-key-auth-vm-mcp.yaml` to resources list.

- [ ] **Step 3: Add middleware to mcp-vm IngressRoute**

Modify `cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml` — add `- name: api-key-auth-vm-mcp` to the `ingress-routes-lan-https-mcp-vm` IngressRoute's middlewares list (after `lan-ip-whitelist`).

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/traefik/traefik/ingress/observability/api-key-auth-vm-mcp.yaml \
       cluster/apps/traefik/traefik/ingress/observability/kustomization.yaml \
       cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml
git commit -m "feat(traefik): add API key auth to VM MCP IngressRoute"
```

## Chunk 3: Network Policies and OpenClaw Integration

### Task 9: Add CiliumNetworkPolicy for mcp-victoriametrics

**Files:**
- Create: `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml`
- Modify: `cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml`

- [ ] **Step 1: Create network-policies.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from Traefik
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-traefik-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-victoriametrics
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: traefik
            k8s:app.kubernetes.io/name: traefik
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow ingress from OpenClaw (pod-to-pod MCP access)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-openclaw-ingress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-victoriametrics
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: openclaw
            k8s:app.kubernetes.io/instance: openclaw
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to VictoriaMetrics
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-victoriametrics-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: mcp-victoriametrics
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmsingle
      toPorts:
        - ports:
            - port: "8428"
              protocol: TCP
```

- [ ] **Step 2: Add network-policies to kustomization**

Modify `cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml` — add `- ./network-policies.yaml` to resources list.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml \
       cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml
git commit -m "feat(observability): add CiliumNetworkPolicies for mcp-victoriametrics"
```

### Task 10: Add OpenClaw CNP egress to kubectl-mcp-server

**Files:**
- Modify: `cluster/apps/openclaw/openclaw/app/network-policies.yaml`

- [ ] **Step 1: Append CNP for kubectl-mcp egress**

Add to end of `cluster/apps/openclaw/openclaw/app/network-policies.yaml`:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow egress to kubectl MCP server
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-mcp-kubectl-egress
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/instance: openclaw
      app.kubernetes.io/name: openclaw
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kubectl-mcp
            k8s:app.kubernetes.io/name: kubectl-mcp-server
      toPorts:
        - ports:
            - port: "8000"
              protocol: TCP
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/openclaw/openclaw/app/network-policies.yaml
git commit -m "feat(openclaw): add CNP egress to kubectl-mcp-server"
```

## Chunk 4: Claude Code Configuration and Cleanup

### Task 11: Update Claude Code MCP configuration

**Files:**
- Modify: `.mcp.json`
- Modify: `.claude/settings.json`

- [ ] **Step 1: Update .mcp.json with both MCP servers and API key headers**

Replace entire `.mcp.json` with:

```json
{
  "mcpServers": {
    "victoriametrics": {
      "type": "http",
      "url": "https://mcp-vm.lan.${EXTERNAL_DOMAIN}/mcp",
      "headers": {
        "X-API-KEY": "${VM_MCP_API_KEY}"
      }
    },
    "kubernetes": {
      "type": "http",
      "url": "https://kubectl-mcp.lan.${EXTERNAL_DOMAIN}/mcp",
      "headers": {
        "X-API-KEY": "${KUBECTL_MCP_API_KEY}"
      }
    }
  }
}
```

- [ ] **Step 2: Remove partial npx mcpServers config from settings.json**

Remove the `mcpServers` block from `.claude/settings.json` (lines 170-178):

```json
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "kubectl-mcp-server"],
      "env": {
        "KUBECONFIG": "/home/vscode/.kube/config"
      }
    }
  },
```

- [ ] **Step 3: Commit**

```bash
git add .mcp.json .claude/settings.json
git commit -m "feat(config): configure MCP servers with API key auth"
```

### Task 12: Run qa-validator

- [ ] **Step 1: Run qa-validator on all changes**

Use the qa-validator agent to validate all files before final push.

### Task 13: Manual steps (user action required)

- [ ] **Step 1: User creates SOPS secret for API keys**

Create `cluster/apps/traefik/traefik/app/mcp-api-keys-secrets.sops.yaml` with generated API keys, then encrypt with SOPS.

- [ ] **Step 2: User updates OpenClaw mcporter.json SOPS secret**

Update `openclaw-workspace-config` SOPS secret to add kubectl-mcp-server endpoint to `mcporter.json`:

```json
{
  "mcpServers": {
    "kubernetes": {
      "type": "http",
      "url": "http://kubectl-mcp-server.kubectl-mcp.svc.cluster.local:8000/mcp"
    }
  }
}
```

Note: OpenClaw connects pod-to-pod, no API key needed (CNP-secured).

- [ ] **Step 3: User sets API key env vars in devcontainer**

Add `KUBECTL_MCP_API_KEY` and `VM_MCP_API_KEY` environment variables to the devcontainer configuration or shell profile.

- [ ] **Step 4: User pushes to main**

- [ ] **Step 5: Run cluster-validator after push**

Use the cluster-validator agent to verify deployment.
