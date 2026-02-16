# Kubernetes Upgrade Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a Claude Code skill that safely orchestrates Kubernetes version upgrades with comprehensive pre-flight checks (breaking changes, API deprecations, health gates) before executing `talosctl upgrade-k8s`.

**Architecture:** Project-level skill at `.claude/skills/kubernetes-upgrade/SKILL.md` with two reference files for progressive disclosure. The SKILL.md contains the core 10-phase workflow (~1,800 words), while detailed lookup and scanning procedures live in `references/`.

**Tech Stack:** Claude Code skills (YAML frontmatter + Markdown), `talosctl`, `kubectl`, `flux` CLI, Context7, GitHub API

**Design doc:** `docs/plans/2026-02-16-kubernetes-upgrade-skill-design.md`

---

### Task 0: Create or find tracking GitHub issue

**All work requires a linked GitHub issue per project constraints. No exceptions.**

**Step 1: Search for existing issue**

```bash
gh issue list --repo anthony-spruyt/spruyt-labs --search "kubernetes-upgrade skill" --label "enhancement"
```

**Step 2: Create issue if none exists**

Read the issue template at `.github/ISSUE_TEMPLATE/feature_request.yml` first to get required fields, then:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(skill): add kubernetes-upgrade skill" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Add a Claude Code skill for safe Kubernetes version upgrades with comprehensive pre-flight safety checks.

## Motivation
Kubernetes upgrades on the Talos cluster currently have no automated pre-flight validation. The talos-upgrade agent handles Talos OS upgrades but there is no equivalent for Kubernetes version upgrades. A skill would ensure breaking changes are researched, deprecated APIs are scanned, and cluster health is verified before executing upgrades.

## Acceptance Criteria
- Skill at `.claude/skills/kubernetes-upgrade/SKILL.md` with frontmatter triggers
- Reference files for breaking changes lookup and API deprecation scanning
- 10-phase workflow with hard gates between phases
- Skill triggers on "upgrade Kubernetes", "upgrade k8s", target version mentions
- Post-upgrade updates to `talos/talconfig.yaml`

## Affected Area
- Tooling (.taskfiles/, scripts)
EOF
)"
```

**Step 3: Record issue number**

Note the issue number (e.g., `#470`). Use this in all subsequent commit messages as `Ref #<number>`.

**Note:** `gh issue create --body` creates a plain markdown issue. The repo uses Issue Forms (`.yml` templates) with dropdown fields like "Affected Area" — these dropdowns won't be populated via CLI. This is a known limitation and is acceptable.

---

### Task 1: Create skill directory structure

**Files:**
- Create: `.claude/skills/kubernetes-upgrade/SKILL.md`
- Create: `.claude/skills/kubernetes-upgrade/references/breaking-changes-lookup.md`
- Create: `.claude/skills/kubernetes-upgrade/references/api-deprecation-scanning.md`

**Step 1: Create directories**

```bash
mkdir -p .claude/skills/kubernetes-upgrade/references
```

**Step 2: Verify structure**

Use Glob tool to verify both directories exist.

---

### Task 2: Write `references/breaking-changes-lookup.md`

Write the detailed reference first since SKILL.md will point to it.

**Files:**
- Create: `.claude/skills/kubernetes-upgrade/references/breaking-changes-lookup.md`

**Step 1: Write the reference file**

Content covers:
- Research priority order (Context7 -> GitHub -> WebFetch -> WebSearch)
- Context7 query patterns for Kubernetes changelogs
- GitHub raw changelog URLs by minor version (`raw.githubusercontent.com/kubernetes/kubernetes/master/CHANGELOG/CHANGELOG-<minor>.md`)
- How to interpret changelog entries (look for "API Changes", "Deprecations", "Removals", "Breaking Changes" sections)
- What to extract: removed APIs, deprecated APIs, behavior changes, feature gates changing default
- How to present findings: structured summary with severity per item
- Talos-specific considerations (Talos bundles kubelet, kube-proxy disabled, CNI is Cilium)

--- BEGIN FILE CONTENT ---

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

--- END FILE CONTENT ---

**Step 2: Verify file**

Read the file back to confirm it was written correctly and is well-structured.

---

### Task 3: Write `references/api-deprecation-scanning.md`

**Files:**
- Create: `.claude/skills/kubernetes-upgrade/references/api-deprecation-scanning.md`

**Step 1: Write the reference file**

Content covers:
- How to scan live cluster for deprecated/removed API usage
- kubectl commands for checking specific API groups
- Metrics-based detection via apiserver request metrics
- Common deprecation patterns across K8s versions
- How to report and remediate findings
- Note: prefer Grep tool for manifest scanning, use kubectl/bash for live cluster queries

--- BEGIN FILE CONTENT ---

# API Deprecation Scanning Reference

## Overview

Before upgrading Kubernetes, scan the live cluster for resources using API versions that will be removed in the target version. This catches issues that dry-run may miss — particularly for resources managed by operators or created dynamically.

## Scanning Methods

### Method 1: Direct Resource Query

For each API being removed, query the cluster directly:

```bash
# Check if a specific deprecated API group/version has resources
kubectl get <resource>.<api-group> --all-namespaces 2>/dev/null

# Examples for common deprecations:
kubectl get flowschemas.flowcontrol.apiserver.k8s.io --all-namespaces 2>/dev/null
kubectl get prioritylevelconfigurations.flowcontrol.apiserver.k8s.io --all-namespaces 2>/dev/null
```

### Method 2: API Server Metrics

Check which API versions are actively being requested:

```bash
# Get API server metrics for deprecated API usage
# Look for requests to deprecated API groups
kubectl get --raw /metrics 2>/dev/null | grep apiserver_requested_deprecated_apis
```

The `apiserver_requested_deprecated_apis` metric tracks:
- `group`: API group
- `version`: API version
- `resource`: Resource type
- `removed_release`: K8s version where API will be removed

Filter for APIs removed in the target version:

```bash
kubectl get --raw /metrics 2>/dev/null | grep apiserver_requested_deprecated_apis | grep 'removed_release="<target-minor>"'
```

### Method 3: Audit Existing Manifests

Scan the git repository for deprecated API versions in manifests. **Use the Grep tool** (not bash grep) per CLAUDE.md tool usage rules:

```
Grep(pattern: "apiVersion: <deprecated-group>/<deprecated-version>", path: "cluster/", glob: "*.yaml")
```

This catches statically defined resources but misses dynamically generated ones (Helm templates, operators).

## Common API Deprecation Patterns

### Flow Control APIs
- `flowcontrol.apiserver.k8s.io/v1beta3` -> `flowcontrol.apiserver.k8s.io/v1` (removed in 1.32)

### Batch APIs
- `batch/v1beta1` CronJob -> `batch/v1` CronJob (removed in 1.25)

### Networking APIs
- `networking.k8s.io/v1beta1` Ingress -> `networking.k8s.io/v1` Ingress (removed in 1.22)

### RBAC APIs
- `rbac.authorization.k8s.io/v1beta1` -> `rbac.authorization.k8s.io/v1` (removed in 1.22)

### Storage APIs
- `storage.k8s.io/v1beta1` CSIDriver -> `storage.k8s.io/v1` CSIDriver (removed in 1.22)

**Note:** This list is not exhaustive. Always cross-reference with the target version's changelog (see `references/breaking-changes-lookup.md`).

## Scanning Procedure

1. **Identify removed APIs** from Phase 1 breaking changes research
2. **Run Method 2 first** (metrics) — fastest, covers dynamic usage
3. **Run Method 1** for each identified removed API — catches currently existing resources
4. **Run Method 3** (Grep tool) — catches manifest definitions
5. **Compile results** with namespace, resource name, and current API version

## Reporting Format

```
## API Compatibility Scan Results

### Resources Using Removed APIs (BLOCKING)
| Namespace | Resource | Kind | Current API | Required Migration |
|-----------|----------|------|-------------|-------------------|
| <ns> | <name> | <kind> | <old-api> | <new-api> |

### Resources Using Deprecated APIs (WARNING)
| Namespace | Resource | Kind | Current API | Removal Version |
|-----------|----------|------|-------------|-----------------|
| <ns> | <name> | <kind> | <old-api> | v<version> |

### Manifest Files Using Deprecated APIs
| File | API Version | Migration |
|------|-------------|-----------|
| <path> | <old-api> | <new-api> |

**Result:** PASS (no removed APIs in use) / BLOCK (removed APIs found — migrate before upgrading)
```

## Remediation

When deprecated APIs are found:

1. **For Helm-managed resources**: Update the Helm chart version or override `apiVersion` in values
2. **For Flux Kustomization resources**: Update the source manifest `apiVersion` field
3. **For operator-managed resources**: Upgrade the operator first (it should handle API migration)
4. **For static manifests**: Edit the YAML to use the new API version

After remediation, re-run the scan to confirm all issues are resolved.

--- END FILE CONTENT ---

**Step 2: Verify file**

Read the file back to confirm correctness.

---

### Task 4: Write `SKILL.md`

**Files:**
- Create: `.claude/skills/kubernetes-upgrade/SKILL.md`

**Step 1: Write the skill file**

Target ~1,800 words. Use imperative/infinitive form (not second person). Third-person description in frontmatter. Reference files in `references/` for detailed procedures.

Frontmatter:

```yaml
---
name: kubernetes-upgrade
description: This skill should be used when the user asks to "upgrade Kubernetes", "upgrade k8s", "update Kubernetes version", mentions a target Kubernetes version like "upgrade to 1.35.1", or when Renovate updates kubernetesVersion in talconfig.yaml. Orchestrates safe Kubernetes upgrades with breaking change research, API deprecation scanning, cluster health gates, dry-run validation, and post-upgrade file updates.
version: 0.1.0
---
```

Body structure (imperative form throughout):

--- BEGIN FILE CONTENT ---

# Kubernetes Upgrade

Orchestrate safe Kubernetes version upgrades on the Talos Linux cluster. The primary value is comprehensive pre-flight safety — researching breaking changes, scanning for deprecated APIs, and gating on cluster health — before executing `talosctl upgrade-k8s`.

## Quick Reference

| Item | Value |
|------|-------|
| Upgrade command | `talosctl upgrade-k8s -n <cp-node> --to v<version>` |
| Config file | `talos/talconfig.yaml` (`kubernetesVersion` field) |
| Node topology | 3 CP (e2-1/2/3), 3 workers (ms-01-1/2/3) |
| Existing agent | `talos-upgrade` handles Talos OS upgrades (different) |
| Expected duration | 5-15 minutes for full cluster |

## Workflow

### Phase 0: Input Parsing

- Parse target version from the user's message (e.g., "upgrade to 1.35.1"). If no version is mentioned, prompt the user for one.
- Read current version from `talos/talconfig.yaml` (`kubernetesVersion` field)
- Validate format (vX.Y.Z), normalize (ensure `v` prefix for commands, strip for comparison)
- Classify: **minor** upgrade (e.g., 1.34 -> 1.35) or **patch** (e.g., 1.35.0 -> 1.35.1)
- Minor upgrades carry higher risk — enforce all gates strictly

### Phase 1: Breaking Changes Research

Consult `references/breaking-changes-lookup.md` for detailed procedures.

1. Query Context7 for Kubernetes changelog/breaking changes
2. If insufficient, fetch changelog from GitHub raw content
3. Summarize: removed APIs, deprecated APIs, behavior changes, notable features
4. Present findings to user

**HARD GATE:** Present breaking changes summary. Wait for user acknowledgment before proceeding. If removed APIs are found that match cluster resources, recommend aborting until remediated.

### Phase 2: Cluster API Compatibility Scan

Consult `references/api-deprecation-scanning.md` for detailed procedures.

1. From Phase 1, identify APIs being removed in target version
2. Scan live cluster via kubectl:
   ```bash
   # Check deprecated API metrics
   kubectl get --raw /metrics 2>/dev/null | grep apiserver_requested_deprecated_apis | grep 'removed_release="<minor>"'
   # Direct resource queries for each removed API
   kubectl get <resource>.<api-group> --all-namespaces 2>/dev/null
   ```
3. Scan git manifests using the Grep tool for deprecated `apiVersion` strings in `cluster/`
4. Report findings with namespace/resource/kind

**HARD GATE:** If removed APIs are in active use, BLOCK upgrade. List resources requiring migration.

### Phase 3: Talos Compatibility Check

Verify Talos supports the target Kubernetes version:

1. Read current Talos version from `talos/talconfig.yaml` (`talosVersion` field)
2. Check Talos support matrix via Context7:
   ```
   resolve-library-id(libraryName: "talos", query: "kubernetes version support matrix")
   query-docs(libraryId: "/siderolabs/talos", query: "supported kubernetes versions for Talos v<current-talos>")
   ```
3. General rule: Talos v1.x supports K8s versions within its tested range

**HARD GATE:** If Talos version is incompatible, BLOCK. Recommend running Talos upgrade first via `talos-upgrade` agent.

### Phase 4: Cluster Health Gate

Discover control plane node IPs dynamically (never hardcode):

```bash
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
```

Run all checks. BLOCK on any failure.

```bash
# Parallel Group 1 - Nodes
kubectl get nodes -o wide
talosctl health -n <first-cp-ip>

# Parallel Group 2 - etcd and Ceph
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Parallel Group 3 - GitOps
flux get kustomizations -A
flux get helmreleases -A
```

**Pass criteria:** All nodes Ready, talosctl health passes, etcd 3 healthy members, Ceph HEALTH_OK, all Flux kustomizations Ready, no failing HelmReleases.

**HARD GATE:** All checks must pass. Report specific failures.

### Phase 5: etcd Backup

Mandatory before upgrade:

```bash
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
talosctl -n $CP_NODE etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot
```

Verify snapshot created successfully.

### Phase 6: Dry Run

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version> --dry-run
```

Report what will change.

**HARD GATE:** Dry run must succeed. Report errors if it fails.

### Phase 7: Execute Upgrade

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version>
```

Monitor: `kubectl get nodes` — wait for all nodes to show new version. Expect 5-15 minutes for the full cluster. If no progress after 20 minutes, investigate with `talosctl dmesg` and `kubectl describe nodes`.

### Phase 8: Post-Upgrade Validation

Re-run Phase 4 health checks plus version verification:

```bash
kubectl version
kubectl get nodes -o wide
```

Confirm all nodes report new Kubernetes version. Report any regressions.

### Phase 9: Update Files & Report

1. Update `kubernetesVersion` in `talos/talconfig.yaml` to match new version
2. Search for old version references using the Grep tool: search for `v<old-version>` in `talos/` and `docs/` with glob `*.md`
3. Update any found references using the Edit tool
4. Present final report:
   - Version change (from -> to)
   - Node status table
   - Health check results
   - Files changed
   - Ready for commit

## Rollback

If the upgrade fails or causes issues:

- `talosctl upgrade-k8s` can be re-run if it fails partway through — it is idempotent
- The etcd backup from Phase 5 is the primary recovery mechanism:
  ```bash
  talosctl -n <cp-node> etcd snapshot restore /tmp/etcd-backup-<timestamp>.snapshot
  ```
- If specific components fail to start after upgrade, check logs:
  ```bash
  talosctl -n <node-ip> logs kubelet
  talosctl -n <node-ip> dmesg
  ```
- For critical failures, consult Talos docs via Context7:
  ```
  query-docs(libraryId: "/siderolabs/talos", query: "kubernetes upgrade rollback recovery")
  ```

## GitHub Issue Tracking

Create or reference a tracking issue per project workflow:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "infra(k8s): upgrade Kubernetes v<current> to v<target>" \
  --label "infra" \
  --body "..."
```

Post progress updates as issue comments after each phase.

## Commit Pattern

```
infra(k8s): upgrade Kubernetes to v<version>

Ref #<issue-number>
```

## Additional Resources

### Reference Files

- **`references/breaking-changes-lookup.md`** — Detailed procedures for researching K8s breaking changes via Context7, GitHub, changelogs
- **`references/api-deprecation-scanning.md`** — kubectl commands, metrics queries, and remediation for deprecated API scanning

--- END FILE CONTENT ---

**Step 2: Word count check**

Verify SKILL.md body is approximately 1,500-2,000 words (target 1,800). Trim or expand as needed.

**Step 3: Verify imperative form**

Scan the written file for second-person language: "you should", "you need", "you can", "you must", "you will", "your". Replace any occurrences with imperative form.

**Step 4: Verify description triggers**

Confirm frontmatter description includes: "upgrade Kubernetes", "upgrade k8s", "update Kubernetes version", target version mentions, Renovate trigger.

---

### Task 5: Validate skill structure

**Step 1: Verify all files exist**

Use Glob tool to check:

```
Glob(pattern: ".claude/skills/kubernetes-upgrade/**/*")
```

Expected files:
- `.claude/skills/kubernetes-upgrade/SKILL.md`
- `.claude/skills/kubernetes-upgrade/references/breaking-changes-lookup.md`
- `.claude/skills/kubernetes-upgrade/references/api-deprecation-scanning.md`

**Step 2: Verify frontmatter**

Read SKILL.md and confirm:
- `name: kubernetes-upgrade`
- `description:` uses third person ("This skill should be used when...") with trigger phrases
- `version: 0.1.0`
- No `argument-hint` field (that is a command feature, not a skill feature)

**Step 3: Verify references are referenced**

Confirm SKILL.md body mentions both reference files by path:
- `references/breaking-changes-lookup.md`
- `references/api-deprecation-scanning.md`

**Step 4: Verify no bash grep in SKILL.md**

Use Grep tool to search SKILL.md for `grep -r` or `grep -rn`. These should not appear — use Grep tool references instead. (Note: bash grep in `kubectl get --raw /metrics | grep` is acceptable since that is a kubectl pipeline, not file searching.)

**Step 5: Run skill-reviewer agent**

Use the `plugin-dev:skill-reviewer` agent to validate the skill follows best practices.

---

### Task 6: Commit skill files

**qa-validator: Skipped** — all files are `*.md` (docs-only changes per validation skip conditions in `.claude/rules/02-validation.md`).

**Step 1: Stage files**

```bash
git add .claude/skills/kubernetes-upgrade/SKILL.md
git add .claude/skills/kubernetes-upgrade/references/breaking-changes-lookup.md
git add .claude/skills/kubernetes-upgrade/references/api-deprecation-scanning.md
```

**Step 2: Commit**

Use the issue number from Task 0:

```bash
git commit -m "$(cat <<'EOF'
feat(skill): add kubernetes-upgrade skill

Adds a Claude Code skill for safe Kubernetes version upgrades with:
- Breaking changes research (Context7, GitHub changelogs)
- Live cluster API deprecation scanning
- Talos compatibility verification
- Cluster health gates (nodes, etcd, Ceph, Flux)
- Dry-run validation
- Post-upgrade file updates (talconfig.yaml, docs)
- Rollback guidance

Ref #<issue-number>
EOF
)"
```

**Step 3: Verify commit**

```bash
git status
git log --oneline -1
```

---

### Task 7: Commit design and plan docs

**qa-validator: Skipped** — all files are `*.md` (docs-only changes).

**Step 1: Stage docs**

```bash
git add docs/plans/2026-02-16-kubernetes-upgrade-skill-design.md
git add docs/plans/2026-02-16-kubernetes-upgrade-skill-plan.md
```

**Step 2: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs(plans): add kubernetes-upgrade skill design and plan

Ref #<issue-number>
EOF
)"
```

---

## Task Dependencies

```
Task 0 (issue) ─┐
                 ├─> Task 1 (dirs) ─┬─> Task 2 (breaking-changes ref) ─┬─> Task 4 (SKILL.md) ─> Task 5 (validate) ─> Task 6 (commit skill) ─> Task 7 (commit docs)
                                    └─> Task 3 (api-deprecation ref) ───┘
```

- Task 0 must complete first (issue number needed for commits)
- Tasks 2 and 3 can run in parallel (independent reference files)
- Task 4 depends on Tasks 2 and 3 (SKILL.md references both files)
- Tasks 5-7 are strictly sequential

## Review Findings Applied

| # | Finding | Fix Applied |
|---|---------|-------------|
| C1 | Missing `version` field in frontmatter | Added `version: 0.1.0` to SKILL.md frontmatter |
| I1 | No GitHub issue task | Added Task 0 with issue search/creation |
| I2 | `$0` vs `$ARGUMENTS` inconsistency | Standardized on `$ARGUMENTS` throughout |
| I4 | Missing qa-validator skip note | Added explicit skip notes to Tasks 6 and 7 |
| I7 | bash grep in SKILL.md body | Replaced with Grep tool references; added validation step in Task 5 |
| C2 | Second-person scan too narrow | Expanded scan to include "you must", "you will", "your" |
| S1 | No rollback procedures | Added Rollback section to SKILL.md body |
| S2 | No timeout guidance | Added expected duration (5-15 min) and 20-min investigation threshold |

### Review 2 Findings Applied

| # | Finding | Fix Applied |
|---|---------|-------------|
| I1 | `argument-hint` and `$ARGUMENTS` are command features, not skill features | Removed `argument-hint` from frontmatter; changed `$ARGUMENTS` to "parse from user's message" |
| I2 | Issue Forms dropdown not populated via CLI | Added note to Task 0 explaining the known limitation |
