# Validator Self-Improvement Feedback Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add self-improvement feedback loops to cluster-validator and qa-validator agents so they accumulate operational knowledge across runs.

**Architecture:** Each validator gets a preloaded skill containing a `known-patterns.md` file. Validators self-record observations before returning verdicts. Callers (renovate-pr-processor) correct wrong verdicts by writing directly to the patterns file.

**Tech Stack:** Claude Code agents, skills (preloaded via `skills:` frontmatter), markdown tables

---

### Task 1: Create cluster-validator-patterns skill

**Files:**
- Create: `.claude/skills/cluster-validator-patterns/SKILL.md`
- Create: `.claude/skills/cluster-validator-patterns/known-patterns.md`

**Step 1: Create SKILL.md**

```markdown
---
name: cluster-validator-patterns
description: Known operational patterns, failure signatures, and false positives for the cluster-validator agent. Preloaded automatically — not user-invocable.
---

# Cluster Validator Known Patterns

Reference file for the cluster-validator agent. Contains accumulated learnings from previous validation runs.

See [known-patterns.md](./known-patterns.md) for the current pattern database.
```

**Step 2: Create known-patterns.md with seed data**

Seed with patterns we already know from recent experience (the firemerge reconciliation chain issue):

```markdown
# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|
| firemerge dependency chain (firefly-iii → firemerge → traefik-ingress) takes 3-5 min to fully reconcile | Full cluster reconciliation wait | 3 | 2026-02-24 | 2026-02-24 |

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
| Kustomization firemerge not ready during reconciliation wave | Dependency chain, resolves within 5 min — wait for full cluster reconciliation | 3 | 2026-02-24 | 2026-02-24 |
```

**Step 3: Commit**

```bash
git add .claude/skills/cluster-validator-patterns/SKILL.md .claude/skills/cluster-validator-patterns/known-patterns.md
git commit -m "feat(skills): create cluster-validator-patterns skill with seed data"
```

---

### Task 2: Create qa-validator-patterns skill

**Files:**
- Create: `.claude/skills/qa-validator-patterns/SKILL.md`
- Create: `.claude/skills/qa-validator-patterns/known-patterns.md`

**Step 1: Create SKILL.md**

```markdown
---
name: qa-validator-patterns
description: Known linting false positives, schema quirks, documentation gaps, and failure signatures for the qa-validator agent. Preloaded automatically — not user-invocable.
---

# QA Validator Known Patterns

Reference file for the qa-validator agent. Contains accumulated learnings from previous validation runs.

See [known-patterns.md](./known-patterns.md) for the current pattern database.
```

**Step 2: Create known-patterns.md (empty tables)**

```markdown
# Known Patterns

## Linting False Positives

MegaLinter or schema check results that are not actual issues.

| Pattern | Tool | Why It's Not a Problem | Count | Last Seen | Added |
|---------|------|----------------------|-------|-----------|-------|

## Schema Quirks

Valid configurations that fail dry-run or schema checks.

| Resource | Quirk | Workaround | Count | Last Seen | Added |
|----------|-------|------------|-------|-----------|-------|

## Documentation Gaps

Cases where Context7 or upstream docs are missing or misleading.

| Library | Gap Description | Correct Behavior | Count | Last Seen | Added |
|---------|----------------|------------------|-------|-----------|-------|

## Failure Signatures

Common validation failures and their known fixes.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|
```

**Step 3: Commit**

```bash
git add .claude/skills/qa-validator-patterns/SKILL.md .claude/skills/qa-validator-patterns/known-patterns.md
git commit -m "feat(skills): create qa-validator-patterns skill with empty tables"
```

---

### Task 3: Add skills preload and self-improvement to cluster-validator

**Files:**
- Modify: `.claude/agents/cluster-validator.md:1-4` (frontmatter — add `skills:` field)
- Modify: `.claude/agents/cluster-validator.md:561-563` (append self-improvement section before closing line)

**Step 1: Add `skills:` to frontmatter**

Change the frontmatter from:

```yaml
---
name: cluster-validator
description: ...
model: opus
---
```

To:

```yaml
---
name: cluster-validator
description: ...
model: opus
skills:
  - cluster-validator-patterns
---
```

**Step 2: Add self-improvement section**

Append before the final closing line (`Your validation should be thorough...`). Insert this new section at line 563, replacing the closing paragraph:

```markdown
## Self-Improvement (MANDATORY — Run Before Returning Result)

After completing validation and determining your verdict, record learnings before returning.

### Step 1: Read current patterns

Read `.claude/skills/cluster-validator-patterns/known-patterns.md` (preloaded via your skill).

### Step 2: Compare this run against known patterns

For each observation from this run (timing behaviors, failure signatures, false positives):

- **Already in table** → Increment Count by 1, update Last Seen to today
- **Not in table** → Append new row with Count=1, Last Seen=today, Added=today
- **No new observations** → Skip to returning result

**What counts as an observation:**
- Timing: "Kustomization X took N minutes to reconcile"
- Failure: "Pod crashed due to X, fixed by Y"
- False positive: "Initially flagged X as failing, but it resolved after waiting"
- Operational: "App X requires special validation steps"

### Step 3: Auto-prune (only when file exceeds 50 total entries across all tables)

- Remove entries where Count=1 AND Added is more than 30 days ago
- Never remove entries with Count >= 3
- Log pruned entries in the commit message

### Step 4: Commit if changed

```bash
git add .claude/skills/cluster-validator-patterns/known-patterns.md
git commit -m "fix(skills): update cluster-validator patterns from run YYYY-MM-DD"
```

Only stage this one file. Never stage other files.

### Step 5: Return result

Return your validation verdict (SUCCESS/ROLLBACK/ROLL-FORWARD) to the calling agent as normal. The self-improvement step must NOT change the verdict.

Your validation should be thorough, evidence-based, and actionable. Never leave the user wondering whether their changes actually worked.
```

**Step 3: Verify the frontmatter is valid**

Read the first 10 lines of the file and confirm `skills:` appears correctly.

**Step 4: Commit**

```bash
git add .claude/agents/cluster-validator.md
git commit -m "feat(agents): add self-improvement feedback loop to cluster-validator"
```

---

### Task 4: Add skills preload and self-improvement to qa-validator

**Files:**
- Modify: `.claude/agents/qa-validator.md:1-5` (frontmatter — add `skills:` field)
- Modify: `.claude/agents/qa-validator.md:525-527` (append self-improvement section before closing line)

**Step 1: Add `skills:` to frontmatter**

Change the frontmatter from:

```yaml
---
name: qa-validator
description: ...
model: opus
---
```

To:

```yaml
---
name: qa-validator
description: ...
model: opus
skills:
  - qa-validator-patterns
---
```

**Step 2: Add self-improvement section**

Append before the final closing line (`You are the last line of defense...`). Insert this new section at line 527, replacing the closing paragraph:

```markdown
## Self-Improvement (MANDATORY — Run Before Returning Result)

After completing validation and determining your verdict, record learnings before returning.

### Step 1: Read current patterns

Read `.claude/skills/qa-validator-patterns/known-patterns.md` (preloaded via your skill).

### Step 2: Compare this run against known patterns

For each observation from this run (linting false positives, schema quirks, doc gaps, failure signatures):

- **Already in table** → Increment Count by 1, update Last Seen to today
- **Not in table** → Append new row with Count=1, Last Seen=today, Added=today
- **No new observations** → Skip to returning result

**What counts as an observation:**
- Linting false positive: "MegaLinter flagged X but it's valid because Y"
- Schema quirk: "Resource X fails dry-run but deploys correctly because Y"
- Documentation gap: "Context7 doesn't have docs for library X, had to use WebFetch"
- Failure signature: "Common error X caused by Y, fix is Z"

### Step 3: Auto-prune (only when file exceeds 50 total entries across all tables)

- Remove entries where Count=1 AND Added is more than 30 days ago
- Never remove entries with Count >= 3
- Log pruned entries in the commit message

### Step 4: Commit if changed

```bash
git add .claude/skills/qa-validator-patterns/known-patterns.md
git commit -m "fix(skills): update qa-validator patterns from run YYYY-MM-DD"
```

Only stage this one file. Never stage other files.

### Step 5: Return result

Return your validation verdict (APPROVED/BLOCKED) to the calling agent as normal. The self-improvement step must NOT change the verdict.

You are the last line of defense before code reaches the cluster. Be thorough, be skeptical, and never rubber-stamp approval.
```

**Step 3: Verify the frontmatter is valid**

Read the first 10 lines of the file and confirm `skills:` appears correctly.

**Step 4: Commit**

```bash
git add .claude/agents/qa-validator.md
git commit -m "feat(agents): add self-improvement feedback loop to qa-validator"
```

---

### Task 5: Add caller correction logic to renovate-pr-processor

**Files:**
- Modify: `.claude/skills/renovate-pr-processor/SKILL.md:162-191` (Step 4.5 — ROLLBACK and ROLL-FORWARD handlers)

**Step 1: Update ROLLBACK handler**

After step 3 (re-run cluster-validator confirms rollback), add a correction step before step 4:

```markdown
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
4. **Record correction**: Compare the first validator run (which triggered ROLLBACK) against the rollback confirmation. If the first run misdiagnosed the issue (e.g., flagged a pre-existing condition as caused by the change), append a correction to `.claude/skills/cluster-validator-patterns/known-patterns.md`:
   - Add to the appropriate table (False Positives, Failure Signatures, or Operational Patterns)
   - Set Count=1, Last Seen=today, Added=today
   - Commit: `fix(skills): update cluster-validator patterns from renovate run <date>`
5. Post comment on the PR explaining the failure and revert
6. Continue to next PR
```

**Step 2: Update ROLL-FORWARD handler**

After step 4 (re-run cluster-validator confirms fix), add a correction step:

```markdown
**On FAILURE (ROLL-FORWARD):**

1. Apply the suggested fix from cluster-validator
2. Commit the fix
3. Ask user to push
4. Re-run cluster-validator to confirm
5. **Record correction**: If the original failure was caused by a pattern not yet in the cluster-validator's known patterns (e.g., a new failure signature), append it to `.claude/skills/cluster-validator-patterns/known-patterns.md`:
   - Add to Failure Signatures table with the error pattern, root cause, and resolution
   - Set Count=1, Last Seen=today, Added=today
   - Commit: `fix(skills): update cluster-validator patterns from renovate run <date>`
6. Continue to next PR
```

**Step 3: Commit**

```bash
git add .claude/skills/renovate-pr-processor/SKILL.md
git commit -m "feat(skills): add caller correction logic to renovate-pr-processor"
```

---

### Task 6: Verify skills preload works

**Step 1: Check that both agent files have valid frontmatter**

Read the first 10 lines of each agent file and confirm `skills:` is present and correctly formatted.

**Step 2: List available skills to confirm the new skills are discoverable**

```bash
ls -la .claude/skills/cluster-validator-patterns/ .claude/skills/qa-validator-patterns/
```

Confirm both directories contain `SKILL.md` and `known-patterns.md`.

**Step 3: Verify the patterns files are valid markdown**

Read both `known-patterns.md` files and confirm:
- Tables have correct column headers
- Seed data in cluster-validator-patterns has correct format
- qa-validator-patterns tables are empty but well-formed

**Step 4: Final commit with all changes**

Run `git status` to confirm only the expected files were modified. If there are any uncommitted changes, commit them.

```bash
git status
```
