# Renovate PR Processor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a skill and subagent that batch-processes open Renovate PRs — analyzing each for breaking changes in parallel, merging safe ones sequentially with cluster validation, and auto-reverting on failures.

**Architecture:** A SKILL.md orchestrates the pipeline (discover → parallel analyze → confirm → sequential merge+validate → summary). A dedicated `renovate-pr-analyzer` agent handles deep analysis of each PR independently. The skill dispatches one agent per PR in parallel, collects results, then merges sequentially.

**Tech Stack:** Claude Code skills/agents, `gh` CLI, `cluster-validator` agent, Context7 for upstream docs

---

### Task 1: Create the `renovate-pr-analyzer` Agent

**Files:**
- Create: `.claude/agents/renovate-pr-analyzer.md`

**Step 1: Create the agent file**

Create `.claude/agents/renovate-pr-analyzer.md` with the following exact content:

```markdown
---
name: renovate-pr-analyzer
description: 'Analyzes a single Renovate PR for breaking changes, deprecations, and upstream issues. Returns a structured SAFE/RISKY/UNKNOWN verdict.\n\n**When to use:**\n- Called by renovate-pr-processor skill during batch PR processing\n- When deep analysis of a dependency update is needed\n\n**When NOT to use:**\n- For non-Renovate PRs\n- For manual dependency updates (analyze manually instead)\n\n**Required input:** PR number and repository name in the prompt.\n\n<example>\nContext: Skill dispatches analysis for a Renovate PR\nuser: "Analyze Renovate PR #499 in anthony-spruyt/spruyt-labs for breaking changes"\nassistant: "Analyzing PR #499..."\n</example>'
model: sonnet
---

You are a dependency update analyst specializing in Kubernetes/GitOps ecosystems. Your role is to deeply analyze a single Renovate PR and return a structured verdict on whether it is safe to merge.

## Core Responsibilities

1. **Read PR metadata and diff** to understand what changed
2. **Classify the dependency type** (Helm chart, container image, taskfile dep, other)
3. **Extract version change** (old version → new version)
4. **Fetch upstream changelog/release notes** for the new version
5. **Search for known issues** with the target version
6. **Evaluate breaking change signals** and return a verdict

## Process

### Step 1: Read PR Details

```bash
# Get PR metadata
gh pr view <number> --repo <repo> --json title,labels,body,files,headRefName

# Get the diff
gh pr diff <number> --repo <repo>
```

### Step 2: Classify Dependency Type

| Label / File Pattern | Type | Upstream Source |
|----------------------|------|----------------|
| `renovate/helm` + `release.yaml` changed | Helm chart | Chart's GitHub repo |
| `renovate/image` + image tag changed | Container image | Image project's GitHub repo |
| `renovate/taskfile` + `.taskfiles/` changed | Taskfile dep | Project's GitHub repo |
| None of the above | Other | Best-effort GitHub search |

### Step 3: Extract Version Change

Parse the diff to find old and new versions. Look for patterns like:
- `version: X.Y.Z` → `version: A.B.C` (Helm chart version)
- `tag: X.Y.Z` → `tag: A.B.C` (container image tag)
- `image: repo:X.Y.Z` → `image: repo:A.B.C`
- `version: X.Y.Z` in Taskfile dependencies

Classify the semver change: patch, minor, or major.

### Step 4: Fetch Upstream Changelog

Follow research priority: Context7 → GitHub → WebFetch → WebSearch (last resort).

**For Helm charts:**
```bash
# Find the chart's source repo from PR body or HelmRepository
# Then check releases
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**For container images:**
```bash
# Find the image project repo
# Check releases/changelog
gh release list --repo <upstream-repo> --limit 10
gh release view <tag> --repo <upstream-repo>
```

**If GitHub releases are sparse, try:**
```
WebFetch: https://raw.githubusercontent.com/<org>/<repo>/main/CHANGELOG.md
```

**Context7 for well-known projects:**
```
resolve-library-id(libraryName: "<project>", query: "changelog breaking changes <version>")
query-docs(libraryId: "<resolved-id>", query: "breaking changes migration <version>")
```

### Step 5: Search for Known Issues

```bash
# Search for bugs/issues with the target version
gh search issues "<project> <target-version>" --limit 10
gh search issues "bug" --repo <upstream-repo> --label bug --limit 10

# Search for breaking change reports
gh search issues "breaking" --repo <upstream-repo> --limit 5
```

### Step 6: Evaluate and Verdict

**Red flag keywords in changelogs/release notes:**
- "breaking", "BREAKING CHANGE", "migration required"
- "removed", "deprecated", "incompatible"
- "CRD update", "schema change", "values changed"
- "requires manual", "action required"

**SAFE criteria (ALL must be true):**
- No breaking change keywords in changelog
- No CRD changes (for Helm charts)
- No values schema changes that affect current config
- No open bugs with high engagement (>5 reactions) for target version
- Patch or minor version bump without breaking changes noted

**RISKY criteria (ANY is true):**
- Breaking change keywords found in changelog
- Major version bump
- CRD changes detected
- Values schema changes that may affect config
- Known bugs with significant engagement
- Migration steps required

**UNKNOWN criteria:**
- Cannot find upstream repo or changelog
- Changelog is empty or unhelpful
- Cannot determine scope of changes

## Output Format (MANDATORY)

Return EXACTLY this format — the orchestrating skill parses it:

```
## VERDICT: [SAFE|RISKY|UNKNOWN]

**PR:** #<number> - <title>
**Dep Type:** [helm|image|taskfile|other]
**Version Change:** <old> → <new> (<patch|minor|major>)

### Reasoning
<2-3 sentences explaining the verdict>

### Breaking Changes
<List of breaking changes found, or "None found">

### Upstream Issues
<List of relevant open issues, or "None found">

### Changelog Summary
<Key changes in the new version, 3-5 bullet points>

### Source
<URLs consulted for this analysis>
```

## Critical Rules

1. **NEVER skip changelog lookup** — always attempt to find release notes
2. **Default to UNKNOWN, not SAFE** — if you cannot find evidence, say so
3. **Check CRD changes for Helm charts** — CRD updates can break existing resources
4. **Follow research priority** — Context7 → GitHub → WebFetch → WebSearch
5. **Be concise** — the orchestrator reads many of these in sequence
6. **Include sources** — always list URLs consulted so user can verify
```

**Step 2: Verify the file was created**

Run: `ls -la .claude/agents/renovate-pr-analyzer.md`
Expected: File exists with non-zero size

**Step 3: Commit**

```bash
git add .claude/agents/renovate-pr-analyzer.md
git commit -m "$(cat <<'EOF'
feat(agents): add renovate-pr-analyzer for dependency update analysis

Subagent that deeply analyzes individual Renovate PRs for breaking
changes. Fetches upstream changelogs, searches for known issues, and
returns structured SAFE/RISKY/UNKNOWN verdicts. Designed to be
dispatched in parallel by the renovate-pr-processor skill.

Ref #<issue-number>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Create the `analysis-patterns.md` Reference

**Files:**
- Create: `.claude/skills/renovate-pr-processor/references/analysis-patterns.md`

**Step 1: Create directory structure**

Run: `mkdir -p .claude/skills/renovate-pr-processor/references`

**Step 2: Create the reference file**

Create `.claude/skills/renovate-pr-processor/references/analysis-patterns.md` with the following exact content:

```markdown
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
```

**Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor/references/analysis-patterns.md
git commit -m "$(cat <<'EOF'
feat(skills): add analysis patterns reference for renovate processor

Reference document covering breaking change detection patterns for Helm
charts, container images, and Taskfile dependencies. Includes upstream
repo discovery, changelog parsing heuristics, and scoring logic.

Ref #<issue-number>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Create the `renovate-pr-processor` SKILL.md

**Files:**
- Create: `.claude/skills/renovate-pr-processor/SKILL.md`

**Step 1: Create the skill file**

Create `.claude/skills/renovate-pr-processor/SKILL.md` with the following exact content:

```markdown
---
name: renovate-pr-processor
description: Use when reviewing, merging, or batch-processing open Renovate dependency update PRs. Triggers on "review renovate PRs", "merge renovate", "process renovate", "batch renovate", "handle renovate PRs", "check renovate PRs", or "/renovate".
argument-hint: ''
---

# Renovate PR Processor

Batch-process all open Renovate PRs: analyze each for breaking changes in parallel, present findings for user confirmation, merge safe ones sequentially with cluster validation between each, and auto-revert on failures.

## Quick Reference

| Item | Value |
|------|-------|
| Analysis agent | `renovate-pr-analyzer` (dispatched per PR) |
| Validation agent | `cluster-validator` (after each merge) |
| Merge strategy | Squash via `gh pr merge --squash` |
| Merge order | patch → minor → major → unlabeled |
| Failure handling | Auto-revert, ask user to push, continue |

## Workflow

### Phase 1: DISCOVER

Fetch all open Renovate PRs and sort by risk level.

```bash
gh pr list --repo anthony-spruyt/spruyt-labs --author "renovate[bot]" \
  --json number,title,labels,headRefName --limit 50
```

Sort PRs by risk level using labels:
1. `dep/patch` — lowest risk
2. `dep/minor` — medium risk
3. `dep/major` — highest risk
4. No `dep/*` label — treat as unknown risk, process last

If no PRs found, report "No open Renovate PRs" and exit.

### Phase 2: ANALYZE (parallel)

Create a GitHub tracking issue for the batch run:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "chore(deps): batch renovate PR processing $(date +%Y-%m-%d)" \
  --label "chore" \
  --body "$(cat <<'ISSUE_EOF'
## Summary
Batch processing of open Renovate dependency update PRs.

## Motivation
Automate review and merge of dependency updates with breaking change analysis and cluster validation.

## Chore Type
Dependency management

## Affected Area
- Apps (cluster/apps/)
ISSUE_EOF
)"
```

Dispatch `renovate-pr-analyzer` agent for EACH PR in parallel using the Task tool:

```
For each PR, use Task tool with:
  subagent_type: "renovate-pr-analyzer"
  run_in_background: true
  prompt: "Analyze Renovate PR #<number> in anthony-spruyt/spruyt-labs for breaking changes.
           Return your analysis in the MANDATORY output format specified in your instructions."
```

Wait for all analysis agents to complete. Collect their verdicts.

### Phase 3: REPORT & CONFIRM

Present a summary table to the user:

```
## Renovate PR Analysis Results

### SAFE (will merge)
| PR | Title | Version Change | Reasoning |
|----|-------|---------------|-----------|
| #N | ...   | X → Y (patch) | No breaking changes found |

### RISKY (will skip)
| PR | Title | Version Change | Reasoning |
|----|-------|---------------|-----------|
| #N | ...   | X → Y (major) | CRD changes detected |

### UNKNOWN (will skip)
| PR | Title | Reasoning |
|----|-------|-----------|
| #N | ...   | Could not find upstream changelog |

Proceed with merging N SAFE PRs? (You can override any verdict)
```

Wait for user confirmation. The user may:
- Approve as-is
- Promote RISKY/UNKNOWN → merge (override)
- Demote SAFE → skip (override)

### Phase 4: MERGE (sequential)

For each confirmed PR, in risk order (patch → minor → major):

#### Step 4.1: Check merge eligibility

```bash
gh pr view <number> --repo anthony-spruyt/spruyt-labs --json mergeable,mergeStateStatus
```

If not mergeable (conflicts), skip with comment and continue.

#### Step 4.2: Merge

```bash
gh pr merge <number> --squash --repo anthony-spruyt/spruyt-labs
```

#### Step 4.3: Determine if cluster validation is needed

Check what files the PR changed:

```bash
gh pr view <number> --repo anthony-spruyt/spruyt-labs --json files --jq '.files[].path'
```

- If ANY file is under `cluster/` → run cluster-validator (Flux-managed resources changed)
- If files are ONLY in `.taskfiles/`, `docs/`, `.github/`, or other non-cluster paths → skip cluster-validator

#### Step 4.4: Validate (if cluster resources changed)

Pull locally to stay in sync:

```bash
git pull origin main
```

Dispatch `cluster-validator` agent with the tracking issue number:

```
Use Task tool with:
  subagent_type: "cluster-validator"
  prompt: "Validate cluster after merging Renovate PR #<number> (<title>).
           GitHub issue: #<tracking-issue-number>
           Repository: anthony-spruyt/spruyt-labs

           The PR updated <dep-type> from <old-version> to <new-version>.
           Focus validation on the affected namespace/app: <namespace>/<app>."
```

#### Step 4.5: Handle validation result

**On SUCCESS:**
- Post comment on the tracking issue noting successful merge and validation
- Continue to next PR

**On FAILURE (ROLLBACK):**

1. Revert the merge commit locally:
   ```bash
   git pull origin main
   git revert HEAD --no-edit
   ```
2. Ask user to push the revert
3. After user confirms push, re-run cluster-validator to confirm rollback:
   ```
   Dispatch cluster-validator with:
     prompt: "Validate cluster after reverting PR #<number>. Confirm rollback is clean.
              GitHub issue: #<tracking-issue-number>"
   ```
4. Post comment on the PR explaining the failure and revert
5. Continue to next PR

**On FAILURE (ROLL-FORWARD):**

1. Apply the suggested fix from cluster-validator
2. Commit the fix
3. Ask user to push
4. Re-run cluster-validator to confirm
5. Continue to next PR

### Phase 5: SUMMARY

Print final report and post to tracking issue:

```
## Renovate Batch Processing Complete

### Merged Successfully
| PR | Title | Version Change | Cluster Validated |
|----|-------|---------------|-------------------|
| #N | ...   | X → Y         | Yes / Skipped     |

### Skipped (RISKY/UNKNOWN)
| PR | Title | Reason |
|----|-------|--------|
| #N | ...   | Breaking changes: CRD update required |

### Reverted (failed validation)
| PR | Title | Failure Reason |
|----|-------|----------------|
| #N | ...   | Pod CrashLoopBackOff after upgrade |

### Summary
- Total PRs: N
- Merged: N
- Skipped: N
- Reverted: N
- Tracking issue: #<number>
```

Post this summary as a comment on the tracking issue. If all PRs were processed successfully (none reverted), close the tracking issue.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No open Renovate PRs | Report and exit |
| All PRs RISKY/UNKNOWN | Report findings, skip merges, exit |
| PR has merge conflicts | Skip with comment, continue to next |
| Cluster-validator times out | Treat as failure, follow ROLLBACK path |
| Upstream repo not found by analyzer | Verdict is UNKNOWN, skip unless user overrides |
| PR changes only non-cluster files | Skip cluster-validator after merge |
| Multiple PRs touch same app | Process sequentially; second PR may conflict after first merges — check mergeable state |

## Additional Resources

### Reference Files

- **`references/analysis-patterns.md`** — Detailed breaking change detection patterns by dependency type (Helm, image, taskfile), upstream repo discovery, changelog parsing heuristics, and scoring logic
```

**Step 2: Verify the skill structure**

Run: `find .claude/skills/renovate-pr-processor -type f`

Expected output:
```
.claude/skills/renovate-pr-processor/SKILL.md
.claude/skills/renovate-pr-processor/references/analysis-patterns.md
```

**Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor/SKILL.md
git commit -m "$(cat <<'EOF'
feat(skills): add renovate-pr-processor skill for batch PR handling

Orchestration skill that batch-processes open Renovate PRs through a
5-phase pipeline: discover, parallel analysis via renovate-pr-analyzer
agent, user confirmation, sequential merge with cluster-validator, and
auto-revert on failures.

Ref #<issue-number>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Create GitHub Issue and Update Commit Messages

**Step 1: Create the tracking issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(skills): add renovate PR batch processor skill and agent" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Create a Claude Code skill and companion subagent to batch-process open Renovate PRs with breaking change analysis, cluster validation, and auto-revert on failures.

## Motivation
Renovate PRs accumulate and require repetitive manual review. Automating the analysis and merge process with safety gates (breaking change detection, cluster validation, auto-revert) saves significant time while maintaining cluster stability.

## Acceptance Criteria
- Skill `renovate-pr-processor` exists in `.claude/skills/`
- Agent `renovate-pr-analyzer` exists in `.claude/agents/`
- Skill discovers all open Renovate PRs
- Agent analyzes each PR for breaking changes (changelogs, upstream issues)
- Analysis runs in parallel across all PRs
- User confirms before any merges happen
- Merges happen sequentially with cluster-validator between each
- Failed merges are auto-reverted
- Summary report tracks all outcomes

## Affected Area
- Tooling (.taskfiles/, scripts)
EOF
)"
```

**Step 2: Note the issue number**

Capture the issue number from the output (e.g., `#505`).

**Step 3: Amend previous commits with correct issue number**

Use interactive rebase to update the `Ref #<issue-number>` in all three prior commits. Since the plan says no amend, instead: the executing agent should have created the issue FIRST before committing. If commits were already made with `<issue-number>` placeholder, leave them — the issue link is in the PR body instead.

**Alternative (preferred):** Create the issue FIRST before Task 1, then use the real number in all commits. Reorder execution: Task 4 Step 1 → Task 1 → Task 2 → Task 3.

---

### Task 5: Validate Skill and Agent

**Step 1: Verify agent frontmatter parses correctly**

Run: `head -5 .claude/agents/renovate-pr-analyzer.md`

Expected: Valid YAML frontmatter with `name`, `description`, `model` fields.

**Step 2: Verify skill frontmatter parses correctly**

Run: `head -5 .claude/skills/renovate-pr-processor/SKILL.md`

Expected: Valid YAML frontmatter with `name`, `description` fields.

**Step 3: Verify all referenced files exist**

Run: `test -f .claude/skills/renovate-pr-processor/references/analysis-patterns.md && echo "OK" || echo "MISSING"`

Expected: `OK`

**Step 4: Verify no duplicate agent names**

Run: `grep -h "^name:" .claude/agents/*.md | sort | uniq -d`

Expected: No output (no duplicates).

**Step 5: Run qa-validator**

Dispatch qa-validator agent to validate all files before final commit/PR.

---

### Execution Order

**IMPORTANT:** Execute in this order to have the issue number available for commits:

1. **Task 4, Step 1-2** — Create GitHub issue, capture number
2. **Task 1** — Create agent (use real issue number in commit)
3. **Task 2** — Create reference file (use real issue number in commit)
4. **Task 3** — Create skill (use real issue number in commit)
5. **Task 5** — Validate everything
