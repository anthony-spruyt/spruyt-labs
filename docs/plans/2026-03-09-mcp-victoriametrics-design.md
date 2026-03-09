# VictoriaMetrics MCP Server Design

## Problem

Querying VictoriaMetrics from Claude Code sessions wastes time on port-forwarding and query syntax. OpenClaw also needs programmatic metrics access.

## Solution

Deploy the [VictoriaMetrics MCP server](https://github.com/VictoriaMetrics/mcp-victoriametrics) as an in-cluster pod in the `observability` namespace, exposed via LAN-only Traefik IngressRoute. Both Claude Code (dev container) and OpenClaw (in-cluster agent) connect as MCP clients.

## Architecture

```text
Dev Container (Claude Code)
  |
  | HTTPS (SSE/Streamable HTTP)
  v
Traefik (lan-ip-whitelist + TLS)
  |
  v
mcp-victoriametrics pod (observability ns, port 8080)
  |                         ^
  | HTTP (cluster DNS)      | HTTP (cluster DNS)
  v                         |
VMSingle (:8428)        OpenClaw pod (openclaw ns)
```

## Deployment

- **Image**: `ghcr.io/victoriametrics-community/mcp-victoriametrics`
- **Helm chart**: bjw-s app-template via existing OCIRepository
- **Namespace**: `observability`
- **Priority**: `low-priority`
- **Resources**: 10m CPU request, 128Mi memory limit
- **Security context**: non-root, read-only root filesystem, drop all capabilities
- **Probes**: `/health/liveness` and `/health/readiness`
- **DependsOn**: `victoria-metrics-k8s-stack`

### Environment Variables

| Variable | Value |
|----------|-------|
| `VM_INSTANCE_ENTRYPOINT` | `http://vmsingle-victoria-metrics-k8s-stack.observability.svc.cluster.local:8428` |
| `VM_INSTANCE_TYPE` | `single` |
| `MCP_SERVER_MODE` | `sse` |
| `MCP_LISTEN_ADDR` | `:8080` |
| `MCP_DISABLED_TOOLS` | omitted — server built-in defaults disable export, flags, debug tools |

## Ingress & Networking

### Traefik IngressRoute

- **Hostname**: `mcp-vm.lan.${EXTERNAL_DOMAIN}`
- **Middlewares**: `lan-ip-whitelist` + `compress`
- **TLS**: cert-manager Certificate via `${CLUSTER_ISSUER}`
- **Location**: `cluster/apps/traefik/traefik/ingress/observability/` (alongside Grafana/VMAgent)

### OpenClaw CNP

New egress policy in `cluster/apps/openclaw/openclaw/app/network-policies.yaml` allowing OpenClaw to reach the MCP server in `observability` namespace on port 8080. Same pattern as existing `allow-n8n-egress`.

### Security Model

Matches existing observability services (Grafana, VMAgent): cluster-internal access unauthenticated, external access LAN-restricted via Traefik IP whitelist + TLS. No bearer token needed.

## MCP Client Configuration

### Claude Code (dev container)

Add to `.mcp.json`:

```json
{
  "mcpServers": {
    "victoriametrics": {
      "type": "sse",
      "url": "https://mcp-vm.lan.<actual-domain>/sse"
    }
  }
}
```

Uses the actual domain value (no Flux substitution in `.mcp.json`).

### OpenClaw (in-cluster)

Add to `mcporter.json` SOPS secret (manual step):

```
http://mcp-victoriametrics-app.observability.svc.cluster.local:8080/sse
```

## Files

### New

| File | Purpose |
|------|---------|
| `cluster/apps/observability/mcp-victoriametrics/ks.yaml` | Flux Kustomization |
| `cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml` | Kustomize resources |
| `cluster/apps/observability/mcp-victoriametrics/app/release.yaml` | HelmRelease (app-template) |
| `cluster/apps/observability/mcp-victoriametrics/app/values.yaml` | bjw-s values |
| `cluster/apps/observability/mcp-victoriametrics/app/kustomizeconfig.yaml` | ConfigMapGenerator name ref |

### Modified

| File | Change |
|------|--------|
| `cluster/apps/observability/kustomization.yaml` | Add `./mcp-victoriametrics/ks.yaml` |
| `cluster/apps/traefik/traefik/ingress/observability/ingress-routes.yaml` | Add IngressRoute |
| `cluster/apps/traefik/traefik/ingress/observability/certificates.yaml` | Add Certificate |
| `cluster/apps/openclaw/openclaw/app/network-policies.yaml` | Add egress CNP |
| `.mcp.json` | Add victoriametrics MCP server |

### Manual Steps

| Action | Why |
|--------|-----|
| Update OpenClaw `mcporter.json` SOPS secret | Contains MCP server URLs, encrypted |
