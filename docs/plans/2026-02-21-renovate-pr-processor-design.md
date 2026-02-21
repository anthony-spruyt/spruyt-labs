# Renovate PR Processor Design

## Overview

A Claude Code skill and companion subagent that batch-processes open Renovate PRs. The skill orchestrates the full pipeline: discover PRs, analyze them for breaking changes in parallel, present findings for user confirmation, merge safe ones sequentially with cluster validation between each, and auto-revert on failures.

## Context

- **Repository**: anthony-spruyt/spruyt-labs (Talos Linux homelab GitOps)
- **Renovate patterns**: PRs labeled `dep/patch`, `dep/minor`, `dep/major`, `renovate/helm`, `renovate/image`, `renovate/taskfile`
- **Existing tooling**: `cluster-validator` agent validates post-merge, `qa-validator` for pre-commit
- **Merge mechanism**: `gh pr merge` operates on remote — no local push needed for merges
- **Revert mechanism**: `git revert` locally, user pushes

## Components

### 1. Skill: `renovate-pr-processor`

**Location:** `.claude/skills/renovate-pr-processor/`

```
.claude/skills/renovate-pr-processor/
├── SKILL.md                          # Core orchestration workflow
└── references/
    └── analysis-patterns.md          # Breaking change detection patterns by dep type
```

**Responsibility:** Orchestrate the full pipeline — discover, dispatch analyzers, present results, merge, validate, revert on failure, report.

### 2. Agent: `renovate-pr-analyzer`

**Location:** `.claude/agents/renovate-pr-analyzer.md`

**Responsibility:** Deep analysis of a single Renovate PR. Receives PR number, fetches diff and upstream changelogs, searches for known issues, returns structured verdict (SAFE/RISKY/UNKNOWN).

## Workflow

### Phase 1: DISCOVER

1. Fetch all open Renovate PRs:
   ```bash
   gh pr list --repo anthony-spruyt/spruyt-labs --author "renovate[bot]" \
     --json number,title,labels,headRefName
   ```
2. Sort by risk level: patch → minor → major → unlabeled
3. If no PRs found, report and exit

### Phase 2: ANALYZE (parallel)

1. Create a GitHub tracking issue for the batch run
2. Dispatch `renovate-pr-analyzer` agent per PR using Task tool (all in parallel, run in background)
3. Each agent returns a structured verdict:
   ```
   VERDICT: SAFE | RISKY | UNKNOWN
   PR: #<number> - <title>
   DEP_TYPE: helm | image | taskfile | other
   CURRENT_VERSION: <version>
   TARGET_VERSION: <version>
   REASONING: <why this verdict>
   BREAKING_CHANGES: <list or "none found">
   UPSTREAM_ISSUES: <list or "none found">
   CHANGELOG_SUMMARY: <key changes>
   ```

### Phase 3: REPORT & CONFIRM

1. Present analysis summary table to user:
   - SAFE PRs (will be merged)
   - RISKY PRs (will be skipped, with reasons)
   - UNKNOWN PRs (will be skipped, with reasons)
2. Ask user to confirm before proceeding
3. User can override: promote RISKY → SAFE, or demote SAFE → skip

### Phase 4: MERGE (sequential, patch → minor → major order)

For each confirmed-SAFE PR:

1. **Merge**: `gh pr merge <number> --squash --repo anthony-spruyt/spruyt-labs`
2. **Pull locally**: `git pull origin main` (keep local in sync for potential reverts)
3. **Validate**: Dispatch `cluster-validator` agent with the tracking issue number
4. **On SUCCESS**: Comment on PR, continue to next
5. **On FAILURE**:
   a. Revert the merge commit: `git revert HEAD --no-edit`
   b. Ask user to push the revert
   c. Re-run cluster-validator to confirm rollback
   d. Comment on PR explaining failure
   e. Continue to next PR

### Phase 5: SUMMARY

Print final report:
- PRs merged successfully (with cluster validation passing)
- PRs skipped (RISKY/UNKNOWN with reasons)
- PRs reverted (merged but failed validation)
- Link to tracking issue

## Agent Design: `renovate-pr-analyzer`

### Input

The skill passes a prompt containing:
- PR number
- Repository name

### Analysis Process

1. **Read PR metadata**: `gh pr view <number> --json title,labels,body,files`
2. **Read PR diff**: `gh pr diff <number>`
3. **Classify dependency type** from labels and file paths:
   - `renovate/helm` + files in `cluster/apps/**/release.yaml` → Helm chart
   - `renovate/image` + files with image tags → Container image
   - `renovate/taskfile` + files in `.taskfiles/` → Taskfile dependency
4. **Extract versions**: Parse old and new versions from the diff
5. **Fetch upstream changelog**:
   - For Helm charts: Check chart repo's GitHub releases
   - For container images: Check image project's GitHub releases or CHANGELOG
   - For taskfile deps: Check project's GitHub releases
   - Use `gh release list --repo <upstream-repo>` and `gh release view <tag> --repo <upstream-repo>`
6. **Search for known issues**:
   - `gh search issues "<project> <version>" --label bug`
   - `gh search issues "<project> breaking" --repo <upstream-repo>`
7. **Evaluate breaking change signals**:
   - Keywords in changelog: "breaking", "migration", "removed", "deprecated", "incompatible"
   - Major version bump
   - CRD changes in Helm charts
   - Values schema changes
   - Known issues with many reactions/comments
8. **Return structured verdict**

### Model

`sonnet` — analysis is parallelized so speed matters more than depth per call. The skill orchestrator (running on the user's model) makes the final decisions.

### Tools

Restricted to read-only: `Bash` (for gh CLI), `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Analysis parallelism | All PRs analyzed in parallel | Analysis is the slow part; merging must be sequential |
| Analysis model | Sonnet | Speed for parallel dispatch; orchestrator makes final call |
| Merge order | patch → minor → major | Lowest risk first; fail fast on easy stuff |
| Merge strategy | Squash | Clean history, one commit per PR |
| Failure handling | Auto-revert and continue | Maximizes throughput; user pushes reverts |
| User confirmation | Required before merges | Safety gate after analysis, before any action |
| Cluster validation | Per-merge via cluster-validator agent | Isolates failures to specific PRs |
| Tracking | GitHub issue per batch run | Audit trail, validator comments |

## Skill Trigger Phrases

- "review renovate PRs"
- "merge renovate PRs"
- "process renovate"
- "batch renovate"
- "handle renovate PRs"
- "check renovate PRs"
- `/renovate`

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No open Renovate PRs | Report "no PRs found" and exit |
| All PRs are RISKY/UNKNOWN | Report findings, skip merges, exit |
| PR has merge conflicts | Skip with comment, continue |
| Cluster-validator times out | Treat as failure, revert |
| Upstream repo not found | Mark as UNKNOWN, explain in reasoning |
| PR modifies non-cluster files only | Skip cluster-validator (no Flux resources affected) |
| Multiple PRs touch same app | Process sequentially; if first fails, skip related ones |

## Progressive Disclosure

### SKILL.md (~1,500-2,000 words)
- Orchestration workflow overview
- Phase descriptions with commands
- Agent dispatch pattern
- Merge/revert procedures
- Summary format

### references/analysis-patterns.md (~2,000 words)
- Helm chart breaking change patterns (CRD changes, values schema, deprecated keys)
- Container image analysis patterns (semver signals, known risky registries)
- Taskfile dependency patterns
- Changelog parsing heuristics
- Red flag keywords and scoring
