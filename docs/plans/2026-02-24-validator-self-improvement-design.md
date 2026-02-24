# Validator Self-Improvement Feedback Loop

## Problem

The cluster-validator and qa-validator agents repeatedly encounter the same operational patterns, failure signatures, and false positives across runs but have no mechanism to learn from them. Each run starts fresh, leading to:

- Re-flagging known slow reconciliation chains as "pre-existing issues"
- Re-investigating failure patterns that have known resolutions
- No accumulation of operational knowledge over time

## Solution

Add a self-improvement feedback loop to both validators using preloaded skills for pattern storage, with split responsibility between validators (self-observed patterns) and callers (wrong-verdict corrections).

## Architecture

### New Skills (Pattern Storage)

```
.claude/skills/cluster-validator-patterns/
├── SKILL.md                  # Minimal skill shell
└── known-patterns.md         # Accumulated runtime learnings

.claude/skills/qa-validator-patterns/
├── SKILL.md                  # Minimal skill shell
└── known-patterns.md         # Accumulated pre-commit learnings
```

Each validator preloads its patterns skill via frontmatter:

```yaml
# cluster-validator.md
---
name: cluster-validator
skills:
  - cluster-validator-patterns
---

# qa-validator.md
---
name: qa-validator
skills:
  - qa-validator-patterns
---
```

### Why Separate Skills Per Validator

QA-validator operates pre-commit (config/syntax/linting domain) while cluster-validator operates post-deploy (runtime/reconciliation domain). Their failure patterns are fundamentally different:

- **QA**: MegaLinter false positives, schema quirks, documentation gaps
- **Cluster**: Reconciliation timing, pod failure signatures, dependency chain behavior

## Known Patterns File Format

### Cluster Validator (`known-patterns.md`)

```markdown
# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
```

### QA Validator (`known-patterns.md`)

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

## Self-Improvement Step (In Each Validator)

Added as the **last step before returning the verdict** to the calling agent. The verdict is already determined — this step only records learnings.

```
## Self-Improvement (MANDATORY — Run Before Returning Result)

### Step 1: Compare this run against known patterns
Read known-patterns.md from your preloaded skill. For each observation
from this run (timing behaviors, failure signatures, false positives):

- **Already in table** → Increment Count, update Last Seen
- **Not in table** → Append new row (Count=1, Last Seen=today, Added=today)
- **No new observations** → Skip to returning result

### Step 2: Auto-prune (only when file exceeds 50 entries)
- Remove entries where Count=1 AND Added >30 days ago
- Never remove entries with Count >= 3
- Log pruned entries in commit message

### Step 3: Commit if changed
- git add the known-patterns.md file (ONLY this file)
- Commit: "fix(skills): update <validator-name> patterns from run <date>"
```

## Caller Correction Logic

When a calling agent (e.g., renovate-pr-processor, feature-dev) observes that a validator gave a wrong verdict:

1. Caller dispatches validator → gets verdict (e.g., ROLLBACK)
2. Caller applies fix or reverts, re-invokes validator → SUCCESS
3. Caller compares first vs second run to identify what was misdiagnosed
4. Caller reads the validator's `known-patterns.md` directly
5. Caller appends the correction (typically to False Positives or Failure Signatures)
6. Caller commits: `fix(skills): update <validator-name> patterns from run <date>`

### Callers That Need Updates

Any skill or prompt that dispatches validators and handles re-invocation:

- `renovate-pr-processor` (Phase 4, Step 4.5 — handles ROLLBACK/ROLL-FORWARD)
- `feature-dev` (if it dispatches validators)
- `add-new-workload` prompt (dispatches cluster-validator after push)
- Any future skill that uses the validation workflow

The caller update is a small addition to the re-invocation logic: after confirming the second run succeeds, compare verdicts and record the correction.

## Auto-Prune Rules

| Condition | Action |
|-----------|--------|
| File exceeds 50 entries | Trigger prune check |
| Count=1 AND Added >30 days ago | Remove (unvalidated, stale) |
| Count >= 3 | Never remove (validated pattern) |
| Count=2 AND Added >30 days ago | Keep (borderline, let it age out naturally) |
| Pruned entries | Log in commit message for auditability |

## Data Flow

```
Validator Run:
  ┌─────────────────────────┐
  │ 1. Run validation       │
  │ 2. Determine verdict    │
  │ 3. Self-improvement:    │
  │    - Read patterns file │
  │    - Compare run obs    │
  │    - Update/append      │
  │    - Auto-prune if >50  │
  │    - Commit if changed  │
  │ 4. Return verdict       │
  └─────────────────────────┘

Caller Correction (on wrong verdict):
  ┌──────────────────────────────┐
  │ 1. Receive wrong verdict     │
  │ 2. Apply fix / revert        │
  │ 3. Re-invoke validator → OK  │
  │ 4. Compare first vs second   │
  │ 5. Write correction to       │
  │    validator's patterns file │
  │ 6. Commit correction         │
  └──────────────────────────────┘
```

## Scope

### In Scope

- New preloaded skills for both validators (pattern storage)
- Self-improvement section in both validator agent prompts
- Caller correction logic in renovate-pr-processor
- Initial empty patterns files (seed with a few known patterns from recent experience)

### Out of Scope

- Caller corrections in feature-dev, add-new-workload (can add later)
- Cross-validator pattern sharing
- Pattern analytics or dashboards
- Automated pattern quality assessment
