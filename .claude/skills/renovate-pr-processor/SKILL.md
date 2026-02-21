---
name: renovate-pr-processor
description: Use when reviewing, merging, or batch-processing open Renovate dependency update PRs. Triggers on "review renovate PRs", "merge renovate", "process renovate", "batch renovate", "handle renovate PRs", "check renovate PRs", or "/renovate".
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
           GitHub issue: #<tracking-issue-number>
           Repository: anthony-spruyt/spruyt-labs
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

### Phase 5b: SELF-IMPROVEMENT

Collect all `### Suggested Improvements` sections from the analyzer agents' outputs. If any suggestions were made:

1. Present them to the user grouped by type:
   ```
   ## Suggested Improvements from This Run

   ### Missing Upstream Repo Mappings
   - <helm-repo-url> → <github-org/repo>

   ### New Changelog Patterns Discovered
   - <description>

   ### Analysis Pattern Gaps
   - <description>

   Apply these improvements to the agent/reference files? (Y/N)
   ```

2. If user approves, apply the improvements:
   - **Repo mappings** → add to `references/analysis-patterns.md` under "Upstream Repo Discovery for Helm Charts"
   - **Changelog patterns** → add to `references/analysis-patterns.md` under "GitHub Release Notes Patterns"
   - **New breaking change signals** → add to `references/analysis-patterns.md` under appropriate dep type section
   - **False positives** → add to "Common NO_IMPACT Scenarios" table

3. Commit improvements with message: `fix(skills): update analysis patterns from renovate batch run <date>`

This feedback loop means the analyzer gets smarter with every batch run.

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
