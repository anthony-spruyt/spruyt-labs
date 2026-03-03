# Analysis Patterns by Dependency Type

## Dependency Type Classification

| Label / File Pattern | Type | Upstream Source |
|----------------------|------|----------------|
| `renovate/helm` + `release.yaml` changed | Helm chart | Chart's GitHub repo |
| `renovate/image` + image tag changed | Container image | Image project's GitHub repo |
| `renovate/taskfile` + `.taskfiles/` changed | Taskfile dep | Project's GitHub repo |
| None of the above | Other | Best-effort GitHub search |

## Breaking Change Signals

### Helm Charts

Charts are in `cluster/apps/<namespace>/<app>/release.yaml` at `spec.chart.spec.version`.

| Signal | Severity | Detection |
|--------|----------|-----------|
| CRD changes | High | "CRD", "CustomResourceDefinition", "kubectl apply --server-side" in notes |
| Values schema changes | High | Renamed/removed keys between versions |
| Removed values keys | High | "removed", "no longer supported" for config keys |
| Default value changes | Medium | Changed defaults may affect behavior silently |
| New required values | Medium | New required fields in release notes |
| Dependency updates | Low | Chart bumps its subcharts |

### Container Images

| Signal | Severity | Detection |
|--------|----------|-----------|
| Major version bump | High | Semver major: 1.x → 2.x |
| Base image change | Medium | "rebased on", "switched to" in notes |
| Config format change | Medium | Config file format changes |
| Env var rename | Medium | Renamed environment variables |
| Dropped architecture | Medium | Check multi-arch if running ARM |

### Taskfile Dependencies

| Signal | Severity | Detection |
|--------|----------|-----------|
| CLI flag changes | High | Removed/renamed flags |
| Output format change | Medium | May break scripts parsing output |
| New required config | Medium | New config file or env var required |

## Upstream Repo Discovery

1. Check agent memory "Upstream Repo Mappings" table first
2. For Helm charts: read HelmRepository source in `cluster/flux/meta/repos/helm/`, derive GitHub org from `spec.url`
3. For images: derive from image name or PR body links
4. For Taskfile deps: URL in Taskfile dependency or version comment

## Changelog Fetch Strategies

Research priority: Context7 → GitHub → WebFetch → WebSearch (last resort).

```bash
# GitHub releases (works for all dep types)
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
- "BREAKING CHANGE", "breaking:", "removed", "no longer supported"
- "migration required", "action required", "incompatible"

**Warning (possibly breaking):**
- "deprecated", "will be removed", "changed default", "renamed", "moved"
- "CRD", "schema change", "API change", "requires", "prerequisite"

**Informational (usually safe):**
- "added", "new feature", "fixed", "bug fix", "improved", "documentation"

### Scoring Heuristic

- 1+ critical keywords → RISKY
- 3+ warning keywords → RISKY
- 1-2 warnings + patch → SAFE (likely future deprecation mentions)
- 1-2 warnings + minor/major → RISKY
- Only informational → SAFE
- No changelog found → UNKNOWN

## Release Notes Formats

**Conventional Commits:** `## Breaking Changes` / `## Features` / `## Bug Fixes`

**Keep a Changelog:** `### Added` / `### Changed` / `### Deprecated` / `### Removed` (check this!) / `### Fixed`

**Helm-specific:** `## Upgrading` / `### From X.x to Y.x` with rename instructions or CRD apply commands

**Extract:** Removed/Breaking section verbatim, Upgrading/Migration section verbatim, Changed section summary, relevant bug fixes.

## Impact Assessment Against Our Config

**The most important analysis step.** A breaking change only matters if it affects what we actually use.

### Config File Locations

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

### Assessment Patterns

| Breaking Change Type | Check | If Found → | If Not Found → |
|---------------------|-------|------------|----------------|
| Helm value renamed/removed | Search values.yaml for old key path | HIGH_IMPACT | NO_IMPACT |
| CRD change | Grep manifests for affected CRD kind + field | HIGH_IMPACT (if field used) | NO_IMPACT |
| Default value changed | Check if we explicitly set the value | NO_IMPACT (our value overrides) | LOW_IMPACT (silent change) |
| Env var renamed | Check values.yaml env/envFrom sections + ConfigMaps | HIGH_IMPACT (if we set it) | NO_IMPACT |
| Config format change | Check for custom config files in app dir | HIGH_IMPACT (if we use old format) | NO_IMPACT |
| API version bump | Grep manifests for old apiVersion | HIGH_IMPACT (must update) | NO_IMPACT |

### Known Patterns

Check agent memory tables for accumulated patterns:
- "Breaking Change False Positives" — changes that don't affect our config
- "Common NO_IMPACT Scenarios" — changes that never matter for this homelab
- "Common HIGH_IMPACT Scenarios" — changes that frequently affect this homelab

## Feature Opportunity Signals

### Keywords (case-insensitive)

**High signal (likely notable feature):**
- "now supports", "introducing", "new feature", "added support for"
- "enabled by default", "native support", "built-in"

**Medium signal (possibly notable):**
- "added", "new option", "new flag", "new parameter"
- "experimental", "beta", "preview", "opt-in"

**Low signal (skip):**
- "internal", "refactor", "cleanup", "minor improvement"
- "documentation", "typo", "CI", "test"

### Relevance Assessment Against Our Config

A new feature is only relevant if it applies to what we deploy.

| Feature Type | Check | HIGH_RELEVANCE | MEDIUM_RELEVANCE | LOW_RELEVANCE |
|-------------|-------|----------------|------------------|---------------|
| New config option | Is the parent feature in our values.yaml? | Yes, and we'd benefit from the option | Yes, but unclear benefit | Parent feature not used |
| New capability | Do we deploy this component? | Yes, replaces a workaround or fills a gap | Yes, but no immediate need | Component not deployed |
| Performance improvement | Do we use the affected codepath? | Yes, and we have resource constraints | Possibly | Unrelated codepath |
| New integration | Do we run both systems? | Yes, currently using manual glue | Yes, one or both deployed | Neither deployed |
| Security feature | Does it affect our exposure? | Yes, hardens something we expose | Possibly relevant | Not applicable |

### Architecture-Aware Matching

Cross-reference features against deployed stack by checking:

1. **CRDs in cluster** — `Grep for 'kind:' in cluster/apps/` to find deployed resource types
2. **Helm values** — Features matching keys in `values.yaml` files
3. **Ingress/networking** — Features related to Cilium, Traefik, Cloudflare patterns we use
4. **Storage** — Features related to Rook Ceph patterns we use
5. **Observability** — Features related to VictoriaMetrics, Grafana patterns we use
