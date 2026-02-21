# Analysis Patterns by Dependency Type

Detailed patterns for detecting breaking changes in different dependency types found in this homelab repository.

## Helm Chart Updates

### Where Helm Charts Live

Helm charts are defined in HelmRelease manifests at `cluster/apps/<namespace>/<app>/release.yaml`. The chart version is in `spec.chart.spec.version`.

### Breaking Change Signals

| Signal | Severity | How to Detect |
|--------|----------|---------------|
| CRD changes | High | Check release notes for "CRD", "CustomResourceDefinition", "kubectl apply --server-side" |
| Values schema changes | High | Compare `values.yaml` structure between versions; look for renamed/removed keys |
| Removed values keys | High | Changelog mentions "removed", "no longer supported" for config keys |
| Default value changes | Medium | Changelog mentions changed defaults; may affect behavior without config changes |
| New required values | Medium | Release notes mention new required fields |
| Dependency updates | Low | Chart bumps its own dependencies (subcharts) |

### Common Helm Chart Patterns

**Traefik:** CRD updates are common and usually backward-compatible. Check for middleware API changes.

**Cert-Manager:** CRD updates require careful review. Check for API version bumps (v1alpha1 → v1).

**Grafana/VictoriaMetrics:** Usually safe. Watch for dashboard schema changes.

**Rook-Ceph:** HIGH RISK. Ceph upgrades can affect data availability. Always check Rook compatibility matrix.

**Cilium:** CRD changes are frequent. Check for CiliumNetworkPolicy API changes. BGP config changes can break routing.

**External-Secrets:** Check for ClusterSecretStore API changes.

### Upstream Repo Discovery for Helm Charts

To find the upstream GitHub repo for a Helm chart:

1. Read the HelmRepository source in `cluster/flux/meta/repos/helm/`:
   ```bash
   grep -r "<chart-name>" cluster/flux/meta/repos/helm/ -l
   ```
2. The `spec.url` points to the Helm repo; derive the GitHub org from it
3. Common mappings:
   - `https://traefik.github.io/charts` → `traefik/traefik-helm-chart`
   - `https://charts.jetstack.io` → `cert-manager/cert-manager`
   - `https://grafana.github.io/helm-charts` → `grafana/helm-charts`
   - `https://charts.rook.io/release` → `rook/rook`
   - `https://helm.cilium.io/` → `cilium/cilium`
   - `https://charts.external-secrets.io` → `external-secrets/external-secrets`
   - `https://bjw-s.github.io/helm-charts` → `bjw-s/helm-charts` (app-template)

## Container Image Updates

### Where Images Live

Container images are referenced in:
- HelmRelease values (inline or via ConfigMap): `image.repository` and `image.tag`
- Raw manifests: `spec.containers[].image`

### Breaking Change Signals

| Signal | Severity | How to Detect |
|--------|----------|---------------|
| Major version bump | High | Semver major: 1.x → 2.x |
| Base image change | Medium | Release notes mention "rebased on", "switched to" |
| Dropped architecture | Medium | Check multi-arch support if running ARM |
| Config format change | Medium | Release notes mention config file format changes |
| Env var rename | Medium | Release notes mention renamed environment variables |
| Entrypoint change | Low | Dockerfile ENTRYPOINT changed |

### Common Image Patterns

**alpine/git:** Usually safe. Minor bumps add git features. Check for removed commands.

**PostgreSQL:** Minor bumps are safe. Major bumps (15→16) require `pg_upgrade`.

**Redis/Valkey:** Minor bumps are usually safe. Check for deprecated commands.

**Grafana:** Usually safe. Check for plugin API changes.

## Taskfile Dependency Updates

### Where Taskfile Deps Live

Taskfile dependencies are in `.taskfiles/` and reference external tools or binaries.

### Breaking Change Signals

| Signal | Severity | How to Detect |
|--------|----------|---------------|
| CLI flag changes | High | Changelog mentions removed/renamed flags |
| Output format change | Medium | May break scripts parsing output |
| New required config | Medium | Tool requires new config file or env var |
| Minimum version bump | Low | Tool requires newer runtime (Go, Node, etc.) |

### Common Taskfile Dependencies

**helmfile:** Check for command syntax changes. Minor bumps are usually safe.

**talhelper:** Check for talconfig.yaml schema changes.

**flux:** Check for CLI command changes.

## Changelog Parsing Heuristics

### Red Flag Keywords (case-insensitive)

**Critical (likely breaking):**
- "BREAKING CHANGE", "breaking:", "⚠️ breaking"
- "removed", "deletion", "no longer supported"
- "migration required", "action required", "manual steps"
- "incompatible", "not backward compatible"

**Warning (possibly breaking):**
- "deprecated", "will be removed"
- "changed default", "new default"
- "renamed", "moved"
- "requires", "prerequisite"
- "CRD", "CustomResourceDefinition"
- "schema change", "API change"

**Informational (usually safe):**
- "added", "new feature", "enhancement"
- "fixed", "bug fix", "patch"
- "improved", "optimized", "performance"
- "documentation", "docs"

### Scoring Heuristic

When multiple signals are present:
- 1+ critical keywords → RISKY
- 3+ warning keywords → RISKY
- 1-2 warning keywords + patch version → SAFE (likely just mentions of future deprecations)
- 1-2 warning keywords + minor/major version → RISKY
- Only informational keywords → SAFE
- No changelog found → UNKNOWN

## GitHub Release Notes Patterns

### Common Formats

**Conventional Commits style:**
```
## Breaking Changes
- feat!: removed X
## Features
- feat: added Y
## Bug Fixes
- fix: resolved Z
```

**Keep a Changelog style:**
```
## [1.2.0] - 2026-01-15
### Added
### Changed
### Deprecated
### Removed    ← CHECK THIS SECTION
### Fixed
### Security
```

**Helm chart specific:**
```
## Upgrading
### From X.x to Y.x
- Rename value `old.key` to `new.key`   ← RISKY
- Run `kubectl apply --server-side`      ← CRD update
```

### What to Extract

1. **Removed/Breaking section** → verbatim quote
2. **Upgrading/Migration section** → verbatim quote
3. **Changed section** → summarize behavior changes
4. **Bug fixes** → note if they fix issues affecting this cluster
