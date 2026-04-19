---
name: renovate-pr-processor
description: Use when reviewing, merging, or batch-processing open Renovate dependency update PRs. Triggers on "review renovate", "merge renovate", "process renovate", "batch renovate", "handle renovate PRs", or "/renovate".
---

# Renovate PR Processor

## Quick Reference

| Item | Value |
|------|-------|
| Analysis agent | `renovate-pr-analyzer` (per PR, parallel) |
| Validation agent | `cluster-validator` (after each merge) |
| Merge strategy | `mcp__github__merge_pull_request` (squash) |
| Merge order | patch → minor → major → unlabeled |
| Failure handling | Auto-revert → user pushes → continue |

## Workflow

### Phase 1: DISCOVER

Use `mcp__github__search_pull_requests`:
- Query: `author:renovate[bot] state:open`
- Owner: `anthony-spruyt`, repo: `spruyt-labs`, perPage: 50

Sort by risk: `dep/patch` → `dep/minor` → `dep/major` → no label. If none found, report and exit.

### Phase 2: ANALYZE (parallel)

Create tracking issue using `mcp__github__issue_write`:
- Method: `create`
- Owner: `anthony-spruyt`, repo: `spruyt-labs`
- Title: `chore(deps): batch renovate PR processing <YYYY-MM-DD>`
- Labels: `["chore"]`
- Body:

```markdown
## Summary
Batch processing of open Renovate dependency update PRs.

## PRs in This Batch
| PR | Title | Risk |
|----|-------|------|
| #N | <title> | patch/minor/major/unknown |

## Chore Type
Dependency management

## Affected Area
- Apps (cluster/apps/)
```

Dispatch `renovate-pr-analyzer` per PR in parallel:

```
Task tool with:
  subagent_type: "renovate-pr-analyzer"
  run_in_background: true
  prompt: "Analyze Renovate PR #<number> in anthony-spruyt/spruyt-labs for breaking changes.
           GitHub issue: #<tracking-issue-number>
           Repository: anthony-spruyt/spruyt-labs"
```

Wait for all agents. Each agent output begins with `## VERDICT: [SAFE|RISKY|UNKNOWN]`. Extract `**Version Change:**`, `**Dep Type:**`, and `### Reasoning` for the Phase 3 summary table.

### Phase 2.5: FEATURE OPPORTUNITIES

After all analyzers complete, collect `### Feature Opportunities` sections from their outputs.

If any HIGH/MEDIUM relevance features found, create issue using `mcp__github__issue_write`:
- Method: `create`
- Owner: `anthony-spruyt`, repo: `spruyt-labs`
- Title: `feat(deps): feature opportunities from renovate batch <YYYY-MM-DD>`
- Labels: `["enhancement"]`
- Body:

```markdown
## Summary
Notable new features from dependency updates that may be relevant to the homelab.

## Feature Opportunities
| PR | Dependency | Feature | Relevance | Why Relevant | Current State |
|----|-----------|---------|-----------|-------------|---------------|
| #N | <dep> | <feature> | HIGH/MEDIUM | <why> | <current> |

## Motivation
These features were identified during automated Renovate PR analysis. Review at your convenience — none affect merge safety.

## Acceptance Criteria
- [ ] Review each listed feature for homelab applicability
- [ ] Create follow-up issues for any features worth implementing

## Affected Area
- Apps (cluster/apps/)
```

If no HIGH/MEDIUM features found across any PR, skip issue creation entirely.

### Phase 3: REPORT & CONFIRM

Present summary table grouped by verdict (SAFE/RISKY/UNKNOWN) with PR number, title, version change, and reasoning. If a feature opportunities issue was created in Phase 2.5, mention it: "Feature opportunities tracked in #&lt;number&gt;." Ask user which PRs to merge. User may override any verdict.

### Phase 4: MERGE (one at a time, risk order: patch → minor → major)

**NEVER merge the next PR until the current PR's validation completes successfully.** If you batch-merge then validate, a ROLLBACK requires reverting through every PR merged after the failure. One at a time.

```dot
digraph merge_loop {
    "Next confirmed PR" [shape=doublecircle];
    "Mergeable?" [shape=diamond];
    "Merge (squash)" [shape=box];
    "Cluster files changed?" [shape=diamond];
    "Run cluster-validator (foreground, blocking)" [shape=box];
    "Validator result?" [shape=diamond];
    "Skip with comment" [shape=box];
    "Handle ROLLBACK/ROLL-FORWARD" [shape=box];
    "More PRs?" [shape=diamond];
    "Phase 5" [shape=doublecircle];

    "Next confirmed PR" -> "Mergeable?";
    "Mergeable?" -> "Skip with comment" [label="no"];
    "Mergeable?" -> "Merge (squash)" [label="yes"];
    "Merge (squash)" -> "Cluster files changed?";
    "Cluster files changed?" -> "More PRs?" [label="no"];
    "Cluster files changed?" -> "Run cluster-validator (foreground, blocking)" [label="yes"];
    "Run cluster-validator (foreground, blocking)" -> "Validator result?";
    "Validator result?" -> "More PRs?" [label="SUCCESS"];
    "Validator result?" -> "Handle ROLLBACK/ROLL-FORWARD" [label="FAILURE"];
    "Handle ROLLBACK/ROLL-FORWARD" -> "More PRs?";
    "Skip with comment" -> "More PRs?";
    "More PRs?" -> "Next confirmed PR" [label="yes"];
    "More PRs?" -> "Phase 5" [label="no"];
}
```

For each confirmed PR (one at a time):

**4.1 Merge:**

1. Check merge status: `mcp__github__pull_request_read` (method: `get`, owner: `anthony-spruyt`, repo: `spruyt-labs`, pullNumber: `<number>`) — check `mergeable` field
2. Merge: `mcp__github__merge_pull_request` (owner: `anthony-spruyt`, repo: `spruyt-labs`, pullNumber: `<number>`, merge_method: `squash`)

If not mergeable (conflicts), skip with comment, continue to next PR.

**4.2 Check if cluster validation needed:**

`mcp__github__pull_request_read` (method: `get_files`, owner: `anthony-spruyt`, repo: `spruyt-labs`, pullNumber: `<number>`)
Files under `cluster/` → run cluster-validator. Only `.taskfiles/`, `docs/`, `.github/` → skip validation, continue to next PR.

**4.3 Validate** (blocking — do NOT merge next PR until this completes): `git pull --ff-only origin main`, then dispatch `cluster-validator` in **foreground** (not background) with tracking issue number, PR details, dep version change, and affected namespace/app.

**4.4 Handle result — resolve fully before next PR:**

- **SUCCESS:** Comment on tracking issue, continue to next PR.
- **ROLLBACK:**
  1. `git pull origin main && git revert HEAD --no-edit`
  2. Ask user to push the revert
  3. Re-run cluster-validator to confirm rollback
  4. **Record correction**: If misdiagnosed, append to `.claude/agent-memory/cluster-validator/known-patterns.md`. Commit: `fix(agents): update cluster-validator patterns from renovate run <date>`
  5. Comment on PR explaining failure/revert, continue to next PR
- **ROLL-FORWARD:**
  1. Apply fix from cluster-validator, commit
  2. Ask user to push, re-run cluster-validator
  3. **Record correction**: If new failure signature, append to `.claude/agent-memory/cluster-validator/known-patterns.md`. Commit: `fix(agents): update cluster-validator patterns from renovate run <date>`
  4. Continue to next PR

### Phase 5: SUMMARY

Post final report to tracking issue: Merged (PR, title, version, validated?), Skipped (PR, title, reason), Reverted (PR, title, failure reason), Feature Opportunities: #&lt;number&gt; (or "None identified"), and totals. Close tracking issue if all PRs processed successfully.

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No open Renovate PRs | Report and exit |
| All PRs RISKY/UNKNOWN | Report findings, skip merges, exit |
| PR has merge conflicts | Skip with comment, continue |
| Cluster-validator times out | Treat as failure, ROLLBACK path |
| Upstream repo not found by analyzer | UNKNOWN verdict, skip unless user overrides |
| PR changes only non-cluster files | Skip cluster-validator after merge |
| Multiple PRs touch same app | Sequential; second may conflict — recheck mergeable state |

## References

- `references/analysis-patterns.md` — Breaking change detection patterns by dependency type
- `.claude/agent-memory/renovate-pr-analyzer/known-patterns.md` — Dynamic learnings from previous runs
