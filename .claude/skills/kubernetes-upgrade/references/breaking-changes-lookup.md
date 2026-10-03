# Breaking Changes Lookup

Research order follows `.claude/rules/research.md`; the steps below apply it to Kubernetes.

## Research Steps

### 1. Context7

```text
resolve-library-id(libraryName: "kubernetes", query: "changelog breaking changes <version>")
query-docs(libraryId: "<resolved-id>", query: "breaking changes removed APIs deprecations v<version>")
```

### 2. GitHub Changelog

```text
WebFetch: https://raw.githubusercontent.com/kubernetes/kubernetes/master/CHANGELOG/CHANGELOG-<minor>.md
Prompt: "Extract breaking changes, removed APIs, deprecated APIs, behavior changes for v<version>"
```

For patch releases, look for the specific patch section header (e.g., `## v1.35.1`).

### 3. GitHub Issues (if changelogs lack detail)

Search GitHub issues for `breaking change v<version>` in `kubernetes/kubernetes`.

### 4. WebSearch (last resort, state why others failed)

## What to Extract

| Severity             | Category                                                                                             | Examples                        | Action                         |
| -------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------ |
| **CRITICAL** (block) | Removed APIs, removed feature gates, breaking kubelet changes                                        | API group removed, gate deleted | BLOCK upgrade until remediated |
| **WARNING**          | Deprecated APIs, feature gate default changes, admission controller changes, metric removals/renames | API deprecated, default flipped | WARN user, plan migration      |
| **Informational**    | New features, performance improvements                                                               | New API, optimization           | Note for awareness             |

## Talos-Specific Filters

| Change Area         | Relevance            | Why                                                                        |
| ------------------- | -------------------- | -------------------------------------------------------------------------- |
| kube-proxy          | Informational only   | Disabled; Cilium handles networking                                        |
| kubelet             | Applies via Talos OS | Talos bundles kubelet                                                      |
| CNI changes         | May not apply        | Cilium is CNI                                                              |
| SSH/systemd changes | N/A                  | Talos has neither                                                          |
| API server flags    | Check patches        | Managed via `talos/patches/control-plane/05-configure-api-server.yaml.tpl` |

## Output

Present as structured summary with sections: Removed APIs (CRITICAL), Deprecated APIs (WARNING), Behavior Changes, Notable Features, Talos-Specific Notes. End with recommendation: PROCEED / CAUTION / ABORT.
