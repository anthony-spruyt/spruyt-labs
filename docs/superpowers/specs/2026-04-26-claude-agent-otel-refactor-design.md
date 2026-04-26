# Claude Agent OTel Telemetry + Kyverno/MCP Refactor

**Issue:** [#1043](https://github.com/anthony-spruyt/spruyt-labs/issues/1043) **Date:** 2026-04-26 **Status:** Draft

## Summary

Add OpenTelemetry instrumentation to Claude agent pods, sending metrics to VMSingle and events/logs to VictoriaLogs via native Claude Code OTel support. Simultaneously refactor Kyverno injection, MCP config, and network policies to per-namespace isolation, introduce `claude-agents-sre` namespace, and remove legacy renovate/homeassistant config. Phase 2 adds VictoriaTraces for distributed tracing.

## Motivation

- Zero visibility into agent cost, token usage, tool execution patterns, or failure rates
- Kyverno policy duplicates identical config across read/write rules
- `SRE_MCP_AUTH_TOKEN` injected into all agent pods — security risk
- MCP access controlled by denylist (settings profiles) instead of allowlist (per-namespace config)
- Legacy renovate MCP config and tokens still present

## Architecture

### Kyverno Rule Structure (Option A — shared + per-namespace)

**ClusterPolicy `inject-claude-agent-config`:**

| Rule                         | Namespaces       | Injects                                                                                                                                          |
| ---------------------------- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `inject-shared-config`       | read, write, sre | Git creds, git config volumes/mounts, `CONTEXT7_API_KEY`, `GH_CONFIG_DIR`, `GIT_CONFIG_GLOBAL`, `MCP_TIMEOUT`, OTel env vars, settings profiles  |
| `inject-read-mcp`            | read             | `claude-mcp-config-read` configmap volume/mount                                                                                                  |
| `inject-write-mcp`           | write            | `claude-mcp-config-write` configmap volume/mount                                                                                                 |
| `inject-sre-mcp`             | sre              | `claude-mcp-config-sre` configmap volume/mount, `SRE_MCP_AUTH_TOKEN` env var (from `sre-credentials` secret), `priorityClassName: high-priority` |
| `inject-read-priority`       | read             | `priorityClassName: low-priority`                                                                                                                |
| `inject-repo-clone-write`    | write            | Clone init container with pre-commit install                                                                                                     |
| `inject-repo-clone-read-sre` | read, sre        | Clone init container without pre-commit (merged — identical logic)                                                                               |

### OTel Environment Variables (Phase 1)

Injected by `inject-shared-config` to all agent pods:

```yaml
- name: CLAUDE_CODE_ENABLE_TELEMETRY
  value: "1"
- name: OTEL_METRICS_EXPORTER
  value: otlp
- name: OTEL_LOGS_EXPORTER
  value: otlp
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: http/protobuf
- name: OTEL_EXPORTER_OTLP_METRICS_ENDPOINT
  value: http://vmsingle-victoria-metrics-k8s-stack.observability.svc:8428/opentelemetry/v1/metrics
- name: OTEL_EXPORTER_OTLP_LOGS_ENDPOINT
  value: http://victoria-logs-single-server.observability.svc:9428/insert/opentelemetry/v1/logs
- name: OTEL_RESOURCE_ATTRIBUTES
  value: "agent.namespace={{request.object.metadata.namespace}}"
```

Export intervals: defaults (60s metrics, 5s logs). Normal pod exit triggers SDK shutdown flush. Abnormal exits (OOM, SIGKILL) lose last batch regardless of interval — not worth optimizing for.

### Per-Namespace MCP ConfigMaps

Three separate configmaps replacing single `claude-mcp-config` + denylist pattern. Each configmap is defined in the shared base but all three deploy to all three namespaces via kustomize. Kyverno per-namespace rules mount only the matching configmap. Extra configmaps in non-matching namespaces are unused but harmless — avoids splitting config across directories.

| Namespace             | MCP Servers                                                           |
| --------------------- | --------------------------------------------------------------------- |
| `claude-agents-read`  | github, context7, bravesearch                                         |
| `claude-agents-write` | github, context7, bravesearch, victoriametrics, kubectl, discord      |
| `claude-agents-sre`   | github, context7, bravesearch, victoriametrics, kubectl, discord, sre |

Removed from all: `renovate`, `homeassistant`.

### Priority Classes

| Namespace             | Priority Class  | Value  | Rationale                              |
| --------------------- | --------------- | ------ | -------------------------------------- |
| `claude-agents-read`  | `low-priority`  | 1000   | Disposable, can re-run                 |
| `claude-agents-write` | `standard`      | 10000  | Mid-commit state damage on eviction    |
| `claude-agents-sre`   | `high-priority` | 100000 | Incident response, must not be evicted |

### Token Injection Per Namespace

| Token                     | read    | write   | sre     |
| ------------------------- | ------- | ------- | ------- |
| `CONTEXT7_API_KEY`        | yes     | yes     | yes     |
| `SRE_MCP_AUTH_TOKEN`      | no      | no      | yes     |
| `HA_API_KEY`              | removed | removed | removed |
| `RENOVATE_MCP_AUTH_TOKEN` | removed | removed | removed |

### Network Policies

**Shared base** (`claude-agents-shared/base/network-policies.yaml`):

- `allow-kube-api-egress` — all agents → kube-apiserver:6443
- `allow-world-egress` — all agents → world (external APIs, npm, git)
- `allow-vmsingle-otlp-egress` — all agents → VMSingle:8428 (NEW)
- `allow-vlogs-otlp-egress` — all agents → VictoriaLogs:9428 (NEW)
- `allow-github-mcp-egress` — all agents → github-mcp:8082
- `allow-brave-search-mcp-egress` — all agents → brave-search-mcp:8000

**Removed from shared** (moved to per-namespace):

- `allow-kubectl-mcp-egress`
- `allow-victoriametrics-mcp-egress`
- `allow-discord-mcp-egress`
- `allow-n8n-mcp-egress`

**Write namespace** (`claude-agents-write/claude-agents/app/network-policies.yaml`):

- `allow-kubectl-mcp-egress` → kubectl-mcp:8000
- `allow-victoriametrics-mcp-egress` → mcp-victoriametrics:8080
- `allow-discord-mcp-egress` → discord-mcp:8080

**SRE namespace** (`claude-agents-sre/claude-agents/app/network-policies.yaml`):

- `allow-kubectl-mcp-egress` → kubectl-mcp:8000
- `allow-victoriametrics-mcp-egress` → mcp-victoriametrics:8080
- `allow-discord-mcp-egress` → discord-mcp:8080
- `allow-n8n-mcp-egress` → n8n-webhook:5678

**MCP server ingress policies** — add `claude-agents-sre` namespace to `fromEndpoints`:

| File                                                                       | Change                    |
| -------------------------------------------------------------------------- | ------------------------- |
| `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`    | Add sre namespace ingress |
| `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`           | Add sre namespace ingress |
| `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml` | Add sre namespace ingress |
| `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml`      | Add sre namespace ingress |
| `cluster/apps/n8n-system/n8n/app/network-policies.yaml`                    | Add sre namespace ingress |
| `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | Add sre namespace ingress |

### New Namespace: `claude-agents-sre`

Mirrors existing read/write structure:

```text
cluster/apps/claude-agents-sre/
├── namespace.yaml                        # PSA restricted
├── kustomization.yaml
└── claude-agents/
    ├── ks.yaml                           # dependsOn: github-token-rotation
    ├── README.md
    └── app/
        ├── kustomization.yaml            # refs shared base + local resources
        ├── github-external-secret.yaml   # read-tier OAuth (SRE doesn't commit)
        ├── sre-credentials.sops.yaml     # Secret `sre-credentials`, key `sre-mcp-auth-token` (user creates)
        └── network-policies.yaml         # SRE-specific MCP egress
```

### Settings Profiles Cleanup

| File                   | Change                              |
| ---------------------- | ----------------------------------- |
| `dev.json`             | Strip `deniedMcpServers`, keep file |
| `pr.json`              | Strip `deniedMcpServers`, keep file |
| `sre.json`             | Strip `deniedMcpServers`, keep file |
| `admin.json`           | No change (already empty)           |
| `renovate-triage.json` | Delete                              |
| `renovate-write.json`  | Delete                              |

### SOPS / Secrets

| Secret                          | Scope              | Change                                                                        |
| ------------------------------- | ------------------ | ----------------------------------------------------------------------------- |
| `mcp-credentials` (shared base) | all namespaces     | Remove `ha-api-key`, `renovate-mcp-auth-token`. Keep `context7-api-key` only. |
| `sre-credentials` (new)         | sre namespace only | Contains `sre-mcp-auth-token`. User creates SOPS file.                        |

### Grafana Dashboard

New `claude-agents.json` in `victoria-metrics-k8s-stack/app/dashboards/`:

| Panel                   | Source                                                | Type              |
| ----------------------- | ----------------------------------------------------- | ----------------- |
| Cost per invocation     | `claude_code_cost_usage` by `agent.namespace`         | Stat + timeseries |
| Token usage             | `claude_code_token_usage` by type                     | Stacked bar       |
| Cache hit rate          | `cacheRead / (input + cacheRead)`                     | Gauge             |
| Active sessions         | `claude_code_session_count` by namespace              | Stat              |
| Tool failures           | VictoriaLogs: `claude_code.tool_result` success=false | Table             |
| Tool duration (p50/p95) | VictoriaLogs: `claude_code.tool_result` duration      | Timeseries        |
| Lines of code           | `claude_code_lines_of_code_count` add/remove          | Timeseries        |
| API errors              | VictoriaLogs: `claude_code.api_error`                 | Table             |

Variables: namespace selector (all/read/write/sre), time range. Datasources: VictoriaMetrics (metrics), VictoriaLogs (events/logs).

## Phase 2: VictoriaTraces

**Chart:** `victoria-traces-single` **OCI URL:** `oci://ghcr.io/victoriametrics/helm-charts/victoria-traces-single` **App version:** v0.8.0, chart v0.0.7 **Port:** 10428 (HTTP) **OTLP endpoint:** `/insert/opentelemetry/v1/traces`

**New files:**

```text
cluster/flux/meta/repositories/oci/victoria-traces-single-ocirepo.yaml

cluster/apps/observability/victoria-traces/
├── ks.yaml
├── README.md
└── app/
    ├── kustomization.yaml
    ├── kustomizeconfig.yaml
    ├── release.yaml
    ├── values.yaml
    ├── vpa.yaml
    └── network-policies.yaml
```

**Kyverno additions** (added to `inject-shared-config`):

```yaml
- name: OTEL_TRACES_EXPORTER
  value: otlp
- name: OTEL_EXPORTER_OTLP_TRACES_ENDPOINT
  value: http://victoria-traces-single.observability.svc:10428/insert/opentelemetry/v1/traces
```

**Network policies:**

- Shared base: agent egress to VictoriaTraces:10428
- VictoriaTraces: ingress from agent namespaces

**Grafana:**

- New Tempo-compatible datasource for VictoriaTraces
- Trace panel in claude-agents dashboard linking log events to trace spans

**Add to `cluster/apps/observability/kustomization.yaml`:** `./victoria-traces/ks.yaml`

**Gating:** Phase 2 depends on Phase 1 deployed and verified. Can be separate PR or follow-up commit.

## File Change Summary

### Modified

| File                                                                       | Change                                                        |
| -------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `cluster/apps/kyverno/policies/app/inject-claude-agent-config.yaml`        | Rewrite: shared + per-namespace rules, OTel, priority classes |
| `cluster/apps/claude-agents-shared/base/network-policies.yaml`             | Remove per-namespace egress, add OTel egress                  |
| `cluster/apps/claude-agents-shared/base/kustomization.yaml`                | Remove renovate profiles, replace MCP configmap with three    |
| `cluster/apps/claude-agents-shared/base/mcp-credentials.sops.yaml`         | Remove `ha-api-key`, `renovate-mcp-auth-token` (user edits)   |
| `cluster/apps/claude-agents-shared/base/settings/dev.json`                 | Strip `deniedMcpServers`                                      |
| `cluster/apps/claude-agents-shared/base/settings/pr.json`                  | Strip `deniedMcpServers`                                      |
| `cluster/apps/claude-agents-shared/base/settings/sre.json`                 | Strip `deniedMcpServers`                                      |
| `cluster/apps/observability/kustomization.yaml`                            | Add victoria-traces reference (Phase 2)                       |
| `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/network-policies.yaml`    | Add sre namespace ingress                                     |
| `cluster/apps/discord-mcp/discord-mcp/app/network-policies.yaml`           | Add sre namespace ingress                                     |
| `cluster/apps/brave-search-mcp/brave-search-mcp/app/network-policies.yaml` | Add sre namespace ingress                                     |
| `cluster/apps/github-mcp/github-mcp-server/app/network-policies.yaml`      | Add sre namespace ingress                                     |
| `cluster/apps/n8n-system/n8n/app/network-policies.yaml`                    | Add sre namespace ingress                                     |
| `cluster/apps/observability/mcp-victoriametrics/app/network-policies.yaml` | Add sre namespace ingress                                     |

### Deleted

| File                                                                   | Reason                               |
| ---------------------------------------------------------------------- | ------------------------------------ |
| `cluster/apps/claude-agents-shared/base/claude-mcp-config.yaml`        | Replaced by per-namespace configmaps |
| `cluster/apps/claude-agents-shared/base/settings/renovate-triage.json` | Legacy                               |
| `cluster/apps/claude-agents-shared/base/settings/renovate-write.json`  | Legacy                               |

### New

| File                                                                                      | Purpose                                               |
| ----------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `cluster/apps/claude-agents-shared/base/claude-mcp-config-read.yaml`                      | Read MCP config (github, context7, bravesearch)       |
| `cluster/apps/claude-agents-shared/base/claude-mcp-config-write.yaml`                     | Write MCP config (+victoriametrics, kubectl, discord) |
| `cluster/apps/claude-agents-shared/base/claude-mcp-config-sre.yaml`                       | SRE MCP config (+sre)                                 |
| `cluster/apps/claude-agents-sre/namespace.yaml`                                           | Namespace, PSA restricted                             |
| `cluster/apps/claude-agents-sre/kustomization.yaml`                                       | Namespace kustomization                               |
| `cluster/apps/claude-agents-sre/claude-agents/ks.yaml`                                    | Flux kustomization                                    |
| `cluster/apps/claude-agents-sre/claude-agents/README.md`                                  | Docs                                                  |
| `cluster/apps/claude-agents-sre/claude-agents/app/kustomization.yaml`                     | Refs shared base                                      |
| `cluster/apps/claude-agents-sre/claude-agents/app/github-external-secret.yaml`            | ESO for GitHub creds                                  |
| `cluster/apps/claude-agents-sre/claude-agents/app/sre-credentials.sops.yaml`              | SRE MCP auth token (user creates)                     |
| `cluster/apps/claude-agents-sre/claude-agents/app/network-policies.yaml`                  | SRE MCP egress                                        |
| `cluster/apps/claude-agents-write/claude-agents/app/network-policies.yaml`                | Write MCP egress                                      |
| `cluster/apps/observability/victoria-metrics-k8s-stack/app/dashboards/claude-agents.json` | Dashboard                                             |
| `cluster/flux/meta/repositories/oci/victoria-traces-single-ocirepo.yaml`                  | Phase 2 OCI repo                                      |
| `cluster/apps/observability/victoria-traces/ks.yaml`                                      | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/README.md`                                    | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/app/kustomization.yaml`                       | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/app/kustomizeconfig.yaml`                     | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/app/release.yaml`                             | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/app/values.yaml`                              | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/app/vpa.yaml`                                 | Phase 2                                               |
| `cluster/apps/observability/victoria-traces/app/network-policies.yaml`                    | Phase 2                                               |

## Out of Scope

- n8n workflow update to spawn SRE agents in new namespace (user does manually)
- SOPS file creation/edits (user does manually)
- Settings profile content beyond denylist cleanup (future use)

## Testing Plan

### Phase 1

- [ ] Verify Kyverno injects OTel env vars: `kubectl describe pod` in each namespace
- [ ] Verify per-namespace MCP configmaps mounted correctly
- [ ] Verify `SRE_MCP_AUTH_TOKEN` only present in sre namespace pods
- [ ] Verify `RENOVATE_MCP_AUTH_TOKEN` and `HA_API_KEY` absent from all pods
- [ ] Run agent in each namespace, query VMSingle for `claude_code_cost_usage` metric
- [ ] Run agent in each namespace, query VictoriaLogs for `claude_code.tool_result` events
- [ ] Verify network policies: read agents cannot reach kubectl-mcp, write agents cannot reach n8n SRE
- [ ] Verify priority classes: read=low-priority, write=standard, sre=high-priority
- [ ] Verify Grafana dashboard renders with real data

### Phase 2

- [ ] VictoriaTraces pod running and healthy
- [ ] Trace spans appear after agent run
- [ ] Grafana Tempo datasource configured and querying
- [ ] Full span waterfall visible in dashboard
