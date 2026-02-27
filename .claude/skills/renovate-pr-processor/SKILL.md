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
| Merge strategy | `gh pr merge --squash` |
| Merge order | patch → minor → major → unlabeled |
| Failure handling | Auto-revert → user pushes → continue |

## Workflow

### Phase 1: DISCOVER

```bash
gh pr list --repo anthony-spruyt/spruyt-labs --author "renovate[bot]" \
  --json number,title,labels,headRefName --limit 50
```

Sort by risk using labels: `dep/patch` (lowest) → `dep/minor` → `dep/major` (highest) → no label (last).

If no PRs found, report and exit.

### Phase 2: ANALYZE (parallel)

Create a GitHub tracking issue for the batch run with all discovered PRs listed:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "chore(deps): batch renovate PR processing $(date +%Y-%m-%d)" \
  --label "chore" \
  --body "$(cat <<'ISSUE_EOF'
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
ISSUE_EOF
)"
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

Wait for all agents to complete. Collect verdicts.

### Phase 3: REPORT & CONFIRM

Present summary table grouped by verdict (SAFE/RISKY/UNKNOWN) with PR number, title, version change, and reasoning. Ask user to confirm which PRs to merge.

User may override any verdict (promote RISKY→merge or demote SAFE→skip).

### Phase 4: MERGE (sequential)

For each confirmed PR, in risk order (patch → minor → major):

#### 4.1: Check eligibility & merge

```bash
gh pr view <number> --repo anthony-spruyt/spruyt-labs --json mergeable,mergeStateStatus
gh pr merge <number> --squash --repo anthony-spruyt/spruyt-labs
```

If not mergeable (conflicts), skip with comment and continue to next PR.

#### 4.2: Determine if cluster validation needed

```bash
gh pr view <number> --repo anthony-spruyt/spruyt-labs --json files --jq '.files[].path'
```

- Files under `cluster/` → run cluster-validator
- Files only in `.taskfiles/`, `docs/`, `.github/` → skip validation

#### 4.3: Validate (if cluster resources changed)

```bash
git pull origin main
```

Dispatch `cluster-validator` with tracking issue number, PR details, dep version change, and affected namespace/app.

#### 4.4: Handle validation result

**SUCCESS:** Post comment on tracking issue, continue to next PR.

**ROLLBACK:**
1. `git pull origin main && git revert HEAD --no-edit`
2. Ask user to push the revert
3. Re-run cluster-validator to confirm rollback
4. **Record correction**: If first run misdiagnosed the issue, append correction to `.claude/agent-memory/cluster-validator/known-patterns.md` (Count=1, Last Seen=today, Added=today). Commit: `fix(agents): update cluster-validator patterns from renovate run <date>`
5. Post comment on PR explaining failure and revert
6. Continue to next PR

**ROLL-FORWARD:**
1. Apply suggested fix from cluster-validator, commit
2. Ask user to push
3. Re-run cluster-validator to confirm
4. **Record correction**: If new failure signature, append to cluster-validator known-patterns. Commit: `fix(agents): update cluster-validator patterns from renovate run <date>`
5. Continue to next PR

### Phase 5: SUMMARY

Post final report to tracking issue with tables for: Merged (PR, title, version, validated?), Skipped (PR, title, reason), Reverted (PR, title, failure reason), and totals.

If all PRs processed successfully (none reverted), close the tracking issue.

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

## References

- `references/analysis-patterns.md` — Breaking change detection patterns by dependency type
- `.claude/agent-memory/renovate-pr-analyzer/known-patterns.md` — Dynamic learnings from previous runs
