# OTEL for Dev Containers — Design Spec

## Overview

Add OpenTelemetry telemetry to dev containers (local and Coder-hosted) by exposing VictoriaMetrics OTLP endpoints through Traefik with API key authentication. Coder workspaces and Claude agents keep hitting `.svc.cluster.local` directly (CNP-only, no auth change).

## Problem

Dev containers run outside cluster, cannot reach `*.svc.cluster.local`. Existing OTEL endpoints (VMSingle, Victoria Logs, Victoria Traces) are internal-only with no auth. Need external ingress with auth for dev container telemetry.

## Architecture

```text
Dev Container (.env mounted)
  └─ OTEL SDK → https://otlp.lan.${EXTERNAL_DOMAIN}/opentelemetry/v1/{metrics,logs,traces}
       └─ Traefik (cert-manager TLS via ${CLUSTER_ISSUER})
            └─ traefik-api-key-auth middleware (Authorization: Bearer <token>)
                 └─ Routes by path prefix:
                      ├─ /opentelemetry/v1/metrics  → vmsingle-victoria-metrics-k8s-stack.observability:8428
                      ├─ /insert/opentelemetry/v1/logs  → victoria-logs-single-server.observability:9428
                      └─ /insert/opentelemetry/v1/traces → victoria-traces-single-vt-single-server.observability:10428

Coder/Agents (internal, unchanged):
  └─ HTTP → *.svc:port/opentelemetry/v1/{metrics,logs,traces}
       └─ CiliumNetworkPolicy controls access (no API key)
```

## Components

### 1. Traefik API Key Auth Middleware

**File:** `cluster/apps/traefik/traefik/ingress/observability/api-key-auth-otel.yaml`

Middleware using existing `traefik-api-key-auth` plugin. Deployed into `observability` namespace via kustomization (same pattern as `lan-ip-whitelist`, `compress`, `rate-limit`).

- Validates `Authorization: Bearer <token>` header
- Key sourced from `env:OTEL_API_KEY` (set on Traefik deployment)
- `removeHeadersOnSuccess: true` — strips auth before forwarding
- No `lan-ip-whitelist` middleware needed — API key is the gate

### 2. Traefik Secret

Key `OTEL_API_KEY` already added to Traefik SOPS secret (`traefik-api-keys`). Traefik deployment env refs it. No new files needed.

### 3. IngressRoute

**File:** `cluster/apps/traefik/traefik/ingress/observability/otlp-ingress.yaml`

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: otlp-lan-https
  namespace: observability
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    external-dns.alpha.kubernetes.io/hostname: otlp.lan.${EXTERNAL_DOMAIN}
spec:
  entryPoints:
    - websecure
  routes:
    - kind: Rule
      match: Host(`otlp.lan.${EXTERNAL_DOMAIN}`) && PathPrefix(`/opentelemetry/v1/metrics`)
      middlewares:
        - name: api-key-auth-otel
          namespace: observability
        - name: compress
      services:
        - name: vmsingle-victoria-metrics-k8s-stack
          namespace: observability
          passHostHeader: true
          port: 8428
    - kind: Rule
      match: Host(`otlp.lan.${EXTERNAL_DOMAIN}`) && PathPrefix(`/insert/opentelemetry/v1/logs`)
      middlewares:
        - name: api-key-auth-otel
          namespace: observability
        - name: compress
      services:
        - name: victoria-logs-single-server
          namespace: observability
          passHostHeader: true
          port: 9428
    - kind: Rule
      match: Host(`otlp.lan.${EXTERNAL_DOMAIN}`) && PathPrefix(`/insert/opentelemetry/v1/traces`)
      middlewares:
        - name: api-key-auth-otel
          namespace: observability
        - name: compress
      services:
        - name: victoria-traces-single-vt-single-server
          namespace: observability
          passHostHeader: true
          port: 10428
  tls:
    secretName: "otlp-lan-${EXTERNAL_DOMAIN/./-}-tls"
```

### 4. Certificate

**File:** Append to `cluster/apps/traefik/traefik/ingress/observability/certificates.yaml`

```yaml
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "otlp-lan-${EXTERNAL_DOMAIN/./-}"
  namespace: observability
spec:
  secretName: "otlp-lan-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - "otlp.lan.${EXTERNAL_DOMAIN}"
```

### 5. Dev Container `.env`

Add to the mounted `.env` (same file used by local and Coder dev containers):

```bash
OTEL_API_KEY=<user-generated-key-same-as-traefik-sops>
OTEL_METRICS_EXPORTER=otlp
OTEL_LOGS_EXPORTER=otlp
OTEL_TRACES_EXPORTER=otlp
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_METRICS_ENDPOINT=https://otlp.lan.${EXTERNAL_DOMAIN}/opentelemetry/v1/metrics
OTEL_EXPORTER_OTLP_LOGS_ENDPOINT=https://otlp.lan.${EXTERNAL_DOMAIN}/insert/opentelemetry/v1/logs
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://otlp.lan.${EXTERNAL_DOMAIN}/insert/opentelemetry/v1/traces
OTEL_RESOURCE_ATTRIBUTES=agent.namespace=devcontainer
```

Plus the existing telemetry flags:

```bash
CLAUDE_CODE_ENABLE_TELEMETRY=1
CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1
OTEL_LOG_TOOL_DETAILS=1
OTEL_LOG_TOOL_CONTENT=1
OTEL_LOG_USER_PROMPTS=1
```

### 6. Kustomization Patch

Add middleware to `observability/kustomization.yaml` with namespace patch:

```yaml
patches:
  - target:
      kind: Middleware
      name: api-key-auth-otel
    patch: |
      - op: replace
        path: /metadata/namespace
        value: observability
```

### 7. Network Policy

No new policy needed. Dev containers connect through Traefik's LAN IP, which already accepts external traffic. API key auth is the access control.

## Coexistence

Coder workspaces and Claude agents continue using internal `.svc.cluster.local` URLs with no auth changes. They are protected by CiliumNetworkPolicies. Dev containers use the new Traefik path with API key auth.

## Rollback

1. Remove `OTEL_*` from dev container `.env`
2. Delete `otlp-ingress.yaml`, remove cert entry from `certificates.yaml`
3. Delete `api-key-auth-otel.yaml`, remove patch from kustomization
4. Remove `OTEL_API_KEY` from Traefik SOPS secret
5. Flux auto-reconciles

## Acceptance Criteria

1. Dev container sends metrics, logs, traces to Victoria\* via HTTPS
2. API key auth validated by Traefik middleware
3. Requests with wrong/missing API key return 403
4. No disruption to Coder workspace or Claude agent telemetry
5. Resource attribution shows `agent.namespace=devcontainer` in Grafana
