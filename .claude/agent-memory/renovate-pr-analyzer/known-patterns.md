# Known Patterns

## Changelog Quirks

Dependency-specific notes about changelog formats, release patterns, and analysis shortcuts.

| Dependency | Quirk | Count | Last Seen | Added |
|------------|-------|------:|-----------|-------|
| n8nio/n8n | Patch changelog body is always empty (cherry-picked from private repo). Use GitHub compare API (`/compare/n8n@X...n8n@Y`) for actual code changes. | 1 | 2026-02-25 | 2026-02-25 |
| n8nio/n8n | `.0` minor releases are always pre-release; they stabilize at `.2`+ (e.g., 2.12.0 pre-release -> 2.12.2 stable; 2.13.0 pre-release -> 2.13.2 stable). Renovate picks up pre-release tags from Docker Hub. Always check `gh release list --repo n8n-io/n8n` and verify `prerelease: false` before approving minor bumps. Release tags use `n8n@X.Y.Z` format (not `vX.Y.Z`). | 4 | 2026-03-25 | 2026-03-18 |
| openclaw/openclaw | GitHub release tags may use `-N` suffix (e.g., `v2026.3.13-1`) when a tag needs re-release due to immutable releases. The npm/Docker version remains the base version (e.g., `2026.3.13`). Try `gh release list` first if exact tag lookup fails. | 1 | 2026-03-16 | 2026-03-16 |
| cloudnative-pg/charts | Monorepo contains multiple charts (`cluster`, `cloudnative-pg`, `plugin-barman-cloud`). Renovate PR body may embed the wrong chart's release notes (e.g., `cluster-v0.6.0` shown for a `plugin-barman-cloud` bump). Always verify against the correctly-tagged release: `gh release view plugin-barman-cloud-vX.Y.Z --repo cloudnative-pg/charts`. | 1 | 2026-04-15 | 2026-04-15 |
| github/github-mcp-server | ghcr.io image tags can appear before a matching git tag/GitHub release is published (Renovate picks up the Docker tag early). If `gh release view <tag>` and `gh api .../git/refs/tags/<tag>` both 404, release is unpublished — default to UNKNOWN and recommend waiting. | 1 | 2026-04-15 | 2026-04-15 |
| github/github-mcp-server | Patch releases can be pure re-tags of the same commit (no code delta). `gh api repos/github/github-mcp-server/compare/vX.Y.Z...vX.Y.(Z+1)` returning `status: "identical"` / `total_commits: 0` means only the image was rebuilt (new digest, same source). Safe to merge — verify with compare API before classifying. | 1 | 2026-04-15 | 2026-04-15 |
| VictoriaMetrics/helm-charts | Chart bumps that rename the pod/selector label (`app` → `app.kubernetes.io/component`) are BREAKING for StatefulSet-backed charts (victoria-logs-single, vmsingle, vmcluster, etc.): `spec.selector.matchLabels` is immutable, Helm upgrade fails with "Forbidden: updates to statefulset spec for fields other than 'replicas'..." and auto-rolls back. Do NOT classify as one-time-restart. Recommend `kubectl delete statefulset <name> --cascade=orphan` during maintenance window before upgrade. Downstream charts adopting the same label convention (see victoria-metrics-operator 0.60.0, victoria-logs-single 0.11.32) share this risk whenever they own a StatefulSet. | 1 | 2026-04-15 | 2026-04-15 |

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
| `n8nio/n8n` (Docker image) | `n8n-io/n8n` | 3 | 2026-03-25 | 2026-02-25 |
| `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator` | `controlplaneio-fluxcd/flux-operator` | 1 | 2026-02-25 | 2026-02-25 |
| `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-instance` | `controlplaneio-fluxcd/flux-operator` (same repo; chart is OCI artifact from operator project) | 1 | 2026-02-25 | 2026-02-25 |
| `oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack` | `VictoriaMetrics/helm-charts` | 1 | 2026-02-25 | 2026-02-25 |
| Velero Helm chart | `vmware-tanzu/helm-charts` (NOT `vmware-tanzu/velero` which is the app repo). Releases tagged `velero-X.Y.Z`. Chart major bumps may embed Velero app major bumps (e.g., chart 12.0.0 = app 1.18.0). | 2 | 2026-03-18 | 2026-02-25 |
| `ghcr.io/openclaw/openclaw` (container image) | `openclaw/openclaw` | 4 | 2026-03-16 | 2026-02-25 |
| `oci://ghcr.io/victoriametrics/helm-charts/victoria-logs-single` | `VictoriaMetrics/helm-charts` (chart repo) + `VictoriaMetrics/VictoriaLogs` (app repo; VictoriaLogs moved to separate repo from VictoriaMetrics) | 1 | 2026-02-26 | 2026-02-26 |
| `redis/redisinsight` (Docker image) | `redis/RedisInsight` | 1 | 2026-02-28 | 2026-02-28 |
| `oci://ghcr.io/kyverno/charts/kyverno` | `kyverno/kyverno` (app repo contains chart; chart version 3.6.x = app v1.16.x) | 1 | 2026-03-10 | 2026-03-10 |
| `ghcr.io/siderolabs/kubelet` (Talos kubelet image) | `siderolabs/kubelet` (mirror repo; actual changelog lives in `kubernetes/kubernetes` CHANGELOG-1.XX.md) | 1 | 2026-03-19 | 2026-03-19 |
| `ghcr.io/siderolabs/installer` (Talos installer image) | `siderolabs/talos` (release tags: `vX.Y.Z`; release notes list component updates, commit log, and dependency changes) | 1 | 2026-03-19 | 2026-03-19 |
| `external-secrets` (Helm chart via HelmRepository) | `external-secrets/external-secrets` (app + chart in same repo; releases tagged `vX.Y.Z`) | 1 | 2026-03-22 | 2026-03-22 |
| `headlamp-plugins/headlamp_flux` (ArtifactHub plugin) | `headlamp-k8s/plugins` (monorepo for all official Headlamp plugins; release tags: `flux-X.Y.Z`; no changelog file, use GitHub release notes) | 1 | 2026-03-23 | 2026-03-23 |
| `headlamp` (Helm chart via HelmRepository) | `kubernetes-sigs/headlamp` (app + chart in same repo; releases tagged `vX.Y.Z`) | 1 | 2026-03-26 | 2026-03-26 |
| `mcporter` (npm package in init script) | `steipete/mcporter` (releases tagged `vX.Y.Z`; changelog in CHANGELOG.md; npm datasource) | 1 | 2026-03-29 | 2026-03-29 |
| `felddy/foundryvtt` (Docker image) | `felddy/foundryvtt-docker` (release tags: `vX.Y.Z`; Docker image version tracks Foundry VTT app version; app release notes at `foundryvtt.com/releases/<version>`) | 1 | 2026-04-03 | 2026-04-03 |
| cloudnative-pg `plugin-barman-cloud` Helm chart | `cloudnative-pg/charts` (monorepo; release tag format: `plugin-barman-cloud-vX.Y.Z`) | 1 | 2026-04-15 | 2026-04-15 |

## Common NO_IMPACT Scenarios

Breaking changes that never matter for this homelab.

| Breaking Change | Why Usually NO_IMPACT | Count | Last Seen | Added |
|----------------|----------------------|------:|-----------|-------|
| openclaw channel-specific breaking changes (Zalo, Telegram, LINE, Feishu, WhatsApp defaults) | We only use Discord; channel-specific breaks for other platforms are irrelevant | 1 | 2026-03-03 | 2026-03-03 |
| openclaw `tools.profile` default changes | We explicitly configure `tools.profile: "full"` so default changes are overridden | 1 | 2026-03-03 | 2026-03-03 |
| openclaw Plugin SDK API changes (`registerHttpHandler` etc.) | We do not develop custom openclaw plugins; only use bundled/community plugins | 1 | 2026-03-03 | 2026-03-03 |

## Common HIGH_IMPACT Scenarios

Breaking changes that frequently affect this homelab.

| Breaking Change | Why Usually HIGH_IMPACT | Count | Last Seen | Added |
|----------------|------------------------|------:|-----------|-------|
| Upstream memory regression (worker/server memory usage increase) | Must cross-reference open performance issues against current resource limits. If new baseline approaches or exceeds limits, OOM restarts will occur. | 1 | 2026-02-25 | 2026-02-25 |
| Velero CSI snapshot restore bugs on Ceph RBD | Rook Ceph + CSI + snapshotMoveData is our primary backup strategy. Any Velero change to VolumeSnapshotContent restore logic (e.g., stripping VolumeSnapshotClassName) breaks DR restore path. Check vmware-tanzu/velero issues for CSI/Ceph/RBD restore before merging. | 1 | 2026-03-18 | 2026-03-18 |
| openclaw Anthropic model initialization regression (TDZ crash on startup) | Our primary model is always Anthropic; any init-order bug in Anthropic model alias resolution will crash gateway on startup. Check openclaw/openclaw issues for `ANTHROPIC_MODEL_ALIASES` or startup crash reports before merging patch releases. Fixed in v2026.3.13 (PR #45520). | 2 | 2026-03-16 | 2026-03-13 |

## Changelog Workarounds

Workarounds in our config that upstream releases may resolve.

| Dependency | Workaround | Upstream Issue | Resolved In | Count | Last Seen | Added |
|------------|-----------|----------------|-------------|------:|-----------|-------|
| headlamp | `config.sessionTTL: null` in values.yaml to prevent `-session-ttl` flag rendering (binary didn't support it) | [#4883](https://github.com/kubernetes-sigs/headlamp/issues/4883) | v0.41.0 (binary now supports `-session-ttl`; safe to remove null override or set explicit value) | 1 | 2026-03-26 | 2026-03-26 |

## Analysis Notes

- `renovate/image` label + `oci/` path in changed files = Helm chart delivered via OCI (treat as Helm chart, not container image, for analysis)
- flux-instance OCIRepository tag tracks the flux-operator chart version, NOT the Flux distribution version — these are independent; distribution version is controlled by `instance.distribution.version` in values.yaml
- Config path: `cluster/flux/meta/repositories/oci/` contains OCI chart sources that are the actual version-pinning mechanism for flux-operator/flux-instance
- Talos installer upgrades require `talosctl upgrade` per node (not GitOps auto-apply). Merging `talconfig.yaml` changes only updates the config source; actual node upgrade is a manual step. Workers running Rook Ceph may freeze during upgrade due to pod unmount delays — use `--staged` flag as workaround (fixed in Talos 1.13)
- Talos `renovate/talos` label = OS-level change; check kernel version bump impact on Cilium BPF (kernel regression history: 6.18.5 broke BPF verifier, patched in pkgs for 6.18.13+)
