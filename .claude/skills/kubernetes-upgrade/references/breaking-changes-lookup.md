# Breaking Changes Lookup Reference

## Research Priority

Follow CLAUDE.md research order. Never skip to WebSearch without exhausting prior steps.

### Step 1: Context7

```
resolve-library-id(libraryName: "kubernetes", query: "changelog breaking changes <version>")
query-docs(libraryId: "<resolved-id>", query: "breaking changes removed APIs deprecations v<version>")
```

If Context7 returns relevant changelog content, extract and summarize. If not, proceed to Step 2.

### Step 2: GitHub Changelog

Fetch the official Kubernetes changelog for the target minor version:

```
WebFetch: https://raw.githubusercontent.com/kubernetes/kubernetes/master/CHANGELOG/CHANGELOG-<minor>.md
Prompt: "Extract all breaking changes, removed APIs, deprecated APIs, and behavior changes for v<version>. Focus on: API removals, feature gate changes, kubelet changes, and anything affecting cluster operations."
```

**URL patterns:**
- v1.35.x: `CHANGELOG/CHANGELOG-1.35.md`
- v1.34.x: `CHANGELOG/CHANGELOG-1.34.md`

For patch releases within a minor version, look for the specific patch section header (e.g., `## v1.35.1`).

### Step 3: GitHub Issues/PRs

If changelogs lack detail on a specific change:

```bash
gh search issues "breaking change v<version>" --repo kubernetes/kubernetes --limit 10
```

### Step 4: WebSearch (Last Resort)

Only after Steps 1-3 fail. State why:

"Context7 and GitHub changelog don't cover <specific topic>, using web search."

## What to Extract

### Critical (BLOCK upgrade)
- **Removed APIs**: APIs that no longer exist. Workloads using them will break.
- **Removed feature gates**: Features removed entirely.
- **Breaking kubelet changes**: Since Talos bundles kubelet, these affect all nodes.

### Important (WARN user)
- **Deprecated APIs**: Still work but will be removed in a future version.
- **Feature gate default changes**: Behavior may change without explicit opt-in/out.
- **Admission controller changes**: May affect workload deployment.
- **Metric removals/renames**: May break monitoring dashboards.

### Informational
- **New features**: Notable additions relevant to the cluster.
- **Performance improvements**: Worth knowing but not blocking.

## Talos-Specific Considerations

This cluster runs Talos Linux, which affects how K8s changes manifest:

- **kube-proxy is disabled** (Cilium handles networking) — kube-proxy deprecations/removals are informational only
- **Talos bundles kubelet** — kubelet changes are applied via Talos OS, not independently
- **CNI is Cilium** — CNI-related changes may not apply
- **No SSH/systemd** — changes to node management tools don't apply
- **API server flags** managed via `talos/patches/control-plane/configure-api-server.yaml`

## Presentation Format

Present findings as a structured summary:

```
## Breaking Changes: v<current> -> v<target>

### Removed APIs (CRITICAL)
- <api>: <description> — **Action required: <migration path>**

### Deprecated APIs (WARNING)
- <api>: <description> — Removal planned in v<future>

### Behavior Changes
- <change>: <description> — Impact: <low/medium/high>

### Notable New Features
- <feature>: <description>

### Talos-Specific Notes
- <any Talos-relevant observations>

**Recommendation:** PROCEED / CAUTION / ABORT
```
