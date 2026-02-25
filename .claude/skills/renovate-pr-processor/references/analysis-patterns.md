# Analysis Patterns by Dependency Type

Detailed patterns for detecting breaking changes in different dependency types found in this homelab repository.

## Dependency Type Classification

Classify each Renovate PR by matching its labels and changed files:

| Label / File Pattern | Type | Upstream Source |
|----------------------|------|----------------|
| `renovate/helm` + `release.yaml` changed | Helm chart | Chart's GitHub repo |
| `renovate/image` + image tag changed | Container image | Image project's GitHub repo |
| `renovate/taskfile` + `.taskfiles/` changed | Taskfile dep | Project's GitHub repo |
| None of the above | Other | Best-effort GitHub search |

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

Check the agent's `known-patterns.md` for dependency-specific quirks accumulated from previous runs. The "Changelog Quirks" table contains per-dependency notes about release patterns and analysis shortcuts.

### Upstream Repo Discovery for Helm Charts

To find the upstream GitHub repo for a Helm chart:

1. Read the HelmRepository source in `cluster/flux/meta/repos/helm/`:
   ```bash
   grep -r "<chart-name>" cluster/flux/meta/repos/helm/ -l
   ```
2. The `spec.url` points to the Helm repo; derive the GitHub org from it
3. Check the agent's `known-patterns.md` "Upstream Repo Mappings" table for previously discovered mappings
4. If not found, derive the GitHub org from the `spec.url` and search GitHub

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

Check the agent's `known-patterns.md` "Changelog Quirks" table for image-specific notes from previous runs.

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

Check the agent's `known-patterns.md` "Changelog Quirks" table for taskfile dependency notes from previous runs.

## Upstream Changelog Fetch Strategies

Follow research priority: Context7 → GitHub → WebFetch → WebSearch (last resort).

**For Helm charts:**

Find the chart's source repo from the PR body or HelmRepository source (see "Upstream Repo Discovery for Helm Charts" above).

```bash
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**For container images:**

Find the image project repo from the image name. Check the PR body for source links, or search GitHub.

```bash
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**For Taskfile dependencies:**

The project repo is usually in the Taskfile dependency URL or version comment.

```bash
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**Fallback — CHANGELOG.md:**

```
WebFetch: https://raw.githubusercontent.com/<org>/<repo>/main/CHANGELOG.md
```

**Context7 for well-known projects:**

```
resolve-library-id(libraryName: "<project>", query: "changelog breaking changes <version>")
query-docs(libraryId: "<resolved-id>", query: "breaking changes migration <version>")
```

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

## Impact Assessment Against Our Config

**The most important analysis step.** A breaking change only matters if it affects what we actually use.

### Where Our Config Lives

```text
cluster/apps/<namespace>/<app>/
├── ks.yaml                    # Kustomization (dependencies, postBuild substitutions)
├── app/
│   ├── kustomization.yaml     # May have configMapGenerator for values
│   ├── release.yaml           # HelmRelease (inline values or valuesFrom)
│   ├── values.yaml            # Helm values — PRIMARY file to check
│   └── *-secrets.sops.yaml    # Encrypted secrets (read key names only)
└── <optional>/                # Ingress routes, network policies, extra CRDs
```

### Impact Assessment Patterns

#### Helm Value Renamed/Removed

```text
Breaking change: "Renamed `ingress.enabled` to `ingress.main.enabled`"

1. Read cluster/apps/<ns>/<app>/app/values.yaml
2. Search for "ingress.enabled" or "ingress:" section
3. If found → HIGH_IMPACT (our config uses the old key path)
4. If not found → NO_IMPACT (we don't configure ingress for this chart)
```

#### CRD Change

```text
Breaking change: "CiliumNetworkPolicy v2 API changed field X"

1. Grep for "kind: CiliumNetworkPolicy" in cluster/apps/ and cluster/flux/
2. If found → check if the changed field is used in our manifests
3. If we have CiliumNetworkPolicy but don't use field X → NO_IMPACT
4. If we use field X → HIGH_IMPACT
```

#### Default Value Changed

```text
Breaking change: "Default replicas changed from 1 to 3"

1. Check if we explicitly set `replicas` in our values.yaml
2. If we set it explicitly → NO_IMPACT (our value overrides the default)
3. If we don't set it → LOW_IMPACT (behavior changes silently)
```

#### Environment Variable Renamed

```text
Breaking change: "Renamed env var DB_HOST to DATABASE_HOST"

1. Check our values.yaml for env/envFrom sections
2. Check any ConfigMaps or secrets that set this env var
3. If we set DB_HOST → HIGH_IMPACT
4. If we don't → NO_IMPACT
```

#### Container Image Config/Env Changes

```text
Breaking change: "Config file format changed from TOML to YAML" or "Env var X removed"

1. Check our values.yaml for env vars or config that references the changed items
2. Check if we mount custom config files (*.json, *.yaml in the app dir) that might be affected
3. Glob for cluster/apps/<ns>/<app>/app/*.{json,yaml} — non-kustomization, non-release, non-sops files
4. If we set the changed env var or use the old config format → HIGH_IMPACT
5. If we don't reference the changed items → NO_IMPACT
```

#### API Version Bumps

```text
Breaking change: "API version changed from v1alpha1 to v1beta1"

1. Search our manifests for the old API version
2. Grep(pattern="apiVersion: <old-version>", path="cluster/apps/<namespace>/")
3. Also check cluster/flux/ for any shared resources using the old API
4. If found → HIGH_IMPACT (manifests must be updated)
5. If not found → NO_IMPACT
```

### Common NO_IMPACT Scenarios

Check the agent's `known-patterns.md` "Common NO_IMPACT Scenarios" and "Breaking Change False Positives" tables for patterns accumulated from previous runs.

### Common HIGH_IMPACT Scenarios

Check the agent's `known-patterns.md` "Common HIGH_IMPACT Scenarios" table for patterns accumulated from previous runs.
