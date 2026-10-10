# Victoria Traces Single - OTLP Trace Storage

## Overview

Trace backend for Claude agents, Coder workspaces, n8n, LiteLLM, Traefik and Falcosidekick. Retention matches VictoriaLogs so trace spans and their log events age out together.

## Operations

### Ingest paths

- **In-cluster**: `http://victoria-traces-single-vt-single-server.observability.svc:10428/insert/opentelemetry/v1/traces`. Standard OTLP clients default to `/v1/traces`; the `/insert/opentelemetry` prefix must be set explicitly or the server returns success for nothing.
- **Dev containers**: `https://otel.lan.${EXTERNAL_DOMAIN}/v1/traces` via Traefik, which rewrites the path and requires the `X-API-KEY` header (`traefik/traefik/ingress/observability/`). Setup is in `DEVELOPMENT.md`.

### Adding a producer

Ingress is allowlisted per producer in `app/network-policies.yaml`. Agent pods are matched on `managed-by: n8n-claude-code` in each `claude-agents-*` namespace, so a new agent namespace needs its own entry. agent-platform web/worker and its agent pods (`managed-by: agent-platform` in `agent-platform-agents`) have their own entry, `allow-agent-platform-traces-ingress`.

Grafana reads traces through the Jaeger-compatible API at `/select/jaeger` (datasource in the k8s-stack values).
