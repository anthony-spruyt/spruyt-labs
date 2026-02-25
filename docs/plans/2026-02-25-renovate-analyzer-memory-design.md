# Renovate PR Analyzer Agent Memory

## Problem

The renovate-pr-analyzer agent starts from scratch each run, re-researching the same dependency types and re-discovering the same patterns. Meanwhile, the skill (`renovate-pr-processor`) has a Phase 5b "SELF-IMPROVEMENT" step that collects "Suggested Improvements" from analyzer outputs and writes them back to `references/analysis-patterns.md` — mixing static reference material with dynamic learnings in a single file, gated behind a manual approval prompt.

This is inconsistent with the self-improvement pattern established for cluster-validator and qa-validator in #541, where agents autonomously accumulate patterns in their own memory.

## Solution

Move dynamic learnings out of `analysis-patterns.md` into agent memory (`known-patterns.md`), add a self-improvement loop to the agent, and remove Phase 5b from the skill.

## Architecture

### File Changes

```
# Modified
.claude/agents/renovate-pr-analyzer.md          # Add memory: project, self-improvement section
.claude/skills/renovate-pr-processor/SKILL.md    # Remove Phase 5b, update Step 0 prompt
.claude/skills/renovate-pr-processor/references/analysis-patterns.md  # Strip dynamic tables

# New
.claude/agent-memory/renovate-pr-analyzer/MEMORY.md
.claude/agent-memory/renovate-pr-analyzer/known-patterns.md
```

### What Moves Where

| Content | From (`analysis-patterns.md`) | To |
|---------|-------------------------------|-----|
| Dependency type classification | Stays | — |
| Breaking change signal tables | Stays | — |
| Changelog fetch strategies | Stays | — |
| Changelog parsing heuristics | Stays | — |
| Impact assessment procedures | Stays | — |
| GitHub release notes formats | Stays | — |
| Upstream repo mappings (lines 57-63) | **Remove** | `known-patterns.md` Upstream Repo Mappings table |
| Common NO_IMPACT scenarios (lines 321-332) | **Remove** | `known-patterns.md` Common NO_IMPACT Scenarios table |
| Common HIGH_IMPACT scenarios (lines 334-345) | **Remove** | `known-patterns.md` Common HIGH_IMPACT Scenarios table |
| Per-chart/image notes (lines 35-43, 86-93) | **Remove** | `known-patterns.md` Changelog Quirks table |

### What Gets Removed

| Content | From | Why |
|---------|------|-----|
| Phase 5b: SELF-IMPROVEMENT | `SKILL.md` (lines 233-261) | Agent handles its own learning now |
| "Suggested Improvements" output section | `renovate-pr-analyzer.md` (lines 157-164) | Replaced by agent writing to its own memory |

## Known Patterns File Format

```markdown
# Known Patterns

## Changelog Quirks

Dependency-specific notes about changelog formats, release patterns, and analysis shortcuts.

| Dependency | Quirk | Count | Last Seen | Added |
|------------|-------|-------|-----------|-------|

## Breaking Change False Positives

Breaking changes flagged by analysis that don't actually affect our config.

| Dependency | Breaking Change | Why NO_IMPACT | Count | Last Seen | Added |
|------------|----------------|---------------|-------|-----------|-------|

## Upstream Repo Mappings

Discovered mappings from Helm repo URLs or image names to GitHub repos.

| Source | GitHub Repo | Count | Last Seen | Added |
|--------|-------------|-------|-----------|-------|

## Common NO_IMPACT Scenarios

Breaking changes that never matter for this homelab.

| Breaking Change | Why Usually NO_IMPACT | Count | Last Seen | Added |
|----------------|----------------------|-------|-----------|-------|

## Common HIGH_IMPACT Scenarios

Breaking changes that frequently affect this homelab.

| Breaking Change | Why Usually HIGH_IMPACT | Count | Last Seen | Added |
|----------------|------------------------|-------|-----------|-------|
```

## Self-Improvement Step (In Agent)

Added as the **last step before returning the verdict**. The verdict is already determined — this step only records learnings.

### Step 1: Read known patterns at start of run

Read `known-patterns.md` from agent memory alongside `analysis-patterns.md`. Use known patterns to inform the analysis (e.g., skip researching a repo mapping already known, apply known NO_IMPACT classifications faster).

### Step 2: Compare this run against known patterns

After determining verdict, for each observation from this run:

- **Already in table** → Increment Count, update Last Seen
- **Not in table** → Append new row (Count=1, Last Seen=today, Added=today)
- **No new observations** → Skip to returning result

What counts as an observation:
- New upstream repo mapping discovered
- Breaking change that turned out to be NO_IMPACT or HIGH_IMPACT for our config
- Changelog format quirk (empty, unusual format, misleading)
- False positive from analysis heuristics

### Step 3: Auto-prune (only when file exceeds 50 entries)

- Remove entries where Count=1 AND Added >30 days ago
- Never remove entries with Count >= 3
- Log pruned entries in commit message

### Step 4: Commit if changed

```bash
git add .claude/agent-memory/renovate-pr-analyzer/known-patterns.md
git commit -m "fix(agents): update renovate-pr-analyzer patterns from run <date>"
```

Only stage this ONE file.

### Step 5: Return verdict

Return the formatted findings as normal. Self-improvement does not change the verdict.

## Skill Changes

### Phase 1 Dispatch Prompt Update

The dispatch prompt currently tells the analyzer to read `analysis-patterns.md`. Update to also mention agent memory:

```
Analysis patterns: .claude/skills/renovate-pr-processor/references/analysis-patterns.md
```

No change needed — the agent's own self-improvement section handles reading its memory. The `memory: project` frontmatter makes the memory directory available.

### Phase 5b Removal

Remove the entire "Phase 5b: SELF-IMPROVEMENT" section (lines 233-261) from `SKILL.md`. The agent now handles pattern accumulation autonomously — no manual approval prompt needed.

### Analyzer Output Format Change

Replace the "Suggested Improvements" section in the mandatory output format with a note that improvements are handled via agent memory. This simplifies the output the skill needs to parse.

## Data Flow

```
Analyzer Run:
  ┌──────────────────────────────────┐
  │ 0. Read analysis-patterns.md     │
  │    Read known-patterns.md        │
  │ 1. Analyze PR (Steps 1-7)       │
  │ 2. Post to tracking issue        │
  │ 3. Self-improvement:             │
  │    - Compare run observations    │
  │    - Update/append patterns      │
  │    - Auto-prune if >50           │
  │    - Commit if changed           │
  │ 4. Return verdict                │
  └──────────────────────────────────┘

Skill (renovate-pr-processor):
  ┌──────────────────────────────────┐
  │ Phase 1: Discover PRs            │
  │ Phase 2: Dispatch analyzers      │
  │ Phase 3: Report & confirm        │
  │ Phase 4: Merge & validate        │
  │ Phase 5: Summary                 │
  │ (No Phase 5b — agent handles it) │
  └──────────────────────────────────┘
```

## Scope

### In Scope

- Add `memory: project` to renovate-pr-analyzer frontmatter
- Create agent memory directory with MEMORY.md and known-patterns.md (empty tables)
- Add self-improvement section to agent system prompt
- Strip dynamic tables from `analysis-patterns.md`
- Remove Phase 5b from skill
- Remove "Suggested Improvements" from analyzer output format

### Out of Scope

- Seeding patterns from previous runs (start empty per user decision)
- Cross-agent pattern sharing
- Caller correction logic for renovate-pr-analyzer (validators already have this)
