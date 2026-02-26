# Known Patterns

## Changelog Quirks

Dependency-specific notes about changelog formats, release patterns, and analysis shortcuts.

| Dependency | Quirk | Count | Last Seen | Added |
|------------|-------|------:|-----------|-------|
| n8nio/n8n | Patch changelog body is always empty (cherry-picked from private repo). Use GitHub compare API (`/compare/n8n@X...n8n@Y`) for actual code changes. | 1 | 2026-02-25 | 2026-02-25 |

## Breaking Change False Positives

Breaking changes flagged by analysis that don't actually affect our config.

| Dependency | Breaking Change | Why NO_IMPACT | Count | Last Seen | Added |
|------------|----------------|---------------|------:|-----------|-------|
| victoria-metrics-k8s-stack | Removed `.Values.defaultDatasources.*.perReplica` | We don't use `perReplica` under `defaultDatasources` | 1 | 2026-02-25 | 2026-02-25 |
| victoria-metrics-k8s-stack | VMProbe `spec.targets.ingress` and `spec.targets.staticConfig` deprecated | We don't deploy any VMProbe resources | 1 | 2026-02-25 | 2026-02-25 |
| authentik | SCIM group syncing behavior changed; existing SCIM providers with `filter_group` deactivated | No SCIM providers defined in any blueprint | 1 | 2026-02-25 | 2026-02-25 |
| authentik | `User.ak_groups` deprecated in favor of `User.groups` | All blueprints use group-based `policybinding`, not expression policies referencing `ak_groups` | 1 | 2026-02-25 | 2026-02-25 |
| flux-instance (flux-operator chart) | Flux v2.8 removes deprecated v1beta2/v2beta2 APIs | Our FluxInstance pins Flux to v2.7.2 via `instance.distribution.version`; no v1beta2/v2beta2 API versions in cluster manifests | 1 | 2026-02-25 | 2026-02-25 |
| openclaw | Heartbeat delivery blocks DM targets | No heartbeat delivery targets configured; default changed from `last` to `none` in same release | 1 | 2026-02-25 | 2026-02-25 |
| openclaw | Docker `network: "container:<id>"` namespace-join blocked for sandbox | No sandbox/Docker config; runs as gateway in K8s with readOnlyRootFilesystem | 1 | 2026-02-25 | 2026-02-25 |

## Upstream Repo Mappings

Discovered mappings from Helm repo URLs or image names to GitHub repos.

| Source | GitHub Repo | Count | Last Seen | Added |
|--------|-------------|------:|-----------|-------|
| `n8nio/n8n` (Docker image) | `n8n-io/n8n` | 1 | 2026-02-25 | 2026-02-25 |
| `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator` | `controlplaneio-fluxcd/flux-operator` | 1 | 2026-02-25 | 2026-02-25 |
| `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance` | `controlplaneio-fluxcd/flux-operator` (same repo; chart is OCI artifact from operator project) | 1 | 2026-02-25 | 2026-02-25 |
| `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack` | `VictoriaMetrics/helm-charts` | 1 | 2026-02-25 | 2026-02-25 |
| Velero Helm chart | `vmware-tanzu/helm-charts` (NOT `vmware-tanzu/velero` which is the app repo). Releases tagged `velero-X.Y.Z`. | 1 | 2026-02-25 | 2026-02-25 |
| `ghcr.io/openclaw/openclaw` (container image) | `openclaw/openclaw` | 1 | 2026-02-25 | 2026-02-25 |
| `oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-single` | `VictoriaMetrics/helm-charts` (chart repo) + `VictoriaMetrics/VictoriaLogs` (app repo; VictoriaLogs moved to separate repo from VictoriaMetrics) | 1 | 2026-02-26 | 2026-02-26 |

## Common NO_IMPACT Scenarios

Breaking changes that never matter for this homelab.

| Breaking Change | Why Usually NO_IMPACT | Count | Last Seen | Added |
|----------------|----------------------|------:|-----------|-------|

## Common HIGH_IMPACT Scenarios

Breaking changes that frequently affect this homelab.

| Breaking Change | Why Usually HIGH_IMPACT | Count | Last Seen | Added |
|----------------|------------------------|------:|-----------|-------|
| Upstream memory regression (worker/server memory usage increase) | Must cross-reference open performance issues against current resource limits. If new baseline approaches or exceeds limits, OOM restarts will occur. | 1 | 2026-02-25 | 2026-02-25 |

## Analysis Notes

- `renovate/image` label + `oci/` path in changed files = Helm chart delivered via OCI (treat as Helm chart, not container image, for analysis)
- flux-instance OCIRepository tag tracks the flux-operator chart version, NOT the Flux distribution version — these are independent; distribution version is controlled by `instance.distribution.version` in values.yaml
- Config path: `cluster/flux/meta/repositories/oci/` contains OCI chart sources that are the actual version-pinning mechanism for flux-operator/flux-instance
