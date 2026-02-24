# Design: Renovate PR Analyzer Patterns Refactor

**Issue:** [#537](https://github.com/anthony-spruyt/spruyt-labs/issues/537)
**Date:** 2026-02-24

## Problem

Phase 5b of `renovate-pr-processor` writes learned patterns to `references/analysis-patterns.md`, but the `renovate-pr-analyzer` agent never reads this file. The self-improvement feedback loop is broken — accumulated knowledge is never consumed.

Additionally, ~60% of the patterns in the reference file are duplicated as baked-in content in the agent. Phase 5b only improves the reference file, so the agent's baked-in patterns never benefit from the feedback loop.

## Design

**Principle:** The agent is a generic _process engine_ (how to analyze). The reference file is the _knowledge base_ (what to look for). The processor skill connects them.

### File Responsibilities

#### Agent (`renovate-pr-analyzer.md`) — Process Engine

Retains the workflow skeleton:

- Frontmatter (name, description, model)
- Role description
- **Step 0 (new):** Read the analysis patterns file from the path provided in the dispatch prompt
- **Step 1:** Read PR details (unchanged — `gh pr view`, `gh pr diff`)
- **Step 2:** Classify dependency type — generic instruction referencing patterns from Step 0 (remove baked-in classification table)
- **Step 3:** Extract version change (unchanged — generic semver parsing)
- **Step 4:** Fetch upstream changelog — generic instruction referencing strategies from Step 0 (remove per-type bash examples)
- **Step 5:** Search for known issues (unchanged — generic `gh search`)
- **Step 6:** Impact analysis — generic instruction referencing patterns from Step 0 (move 6b cross-reference procedures per dep type; keep impact level table inline)
- **Step 7:** Evaluate verdict — keep SAFE/RISKY/UNKNOWN definitions inline; reference scoring heuristic from patterns (remove red flag keywords and per-type criteria)
- **Steps 8-9:** Format, post, return (unchanged)
- Critical rules (unchanged)

#### Reference File (`references/analysis-patterns.md`) — Knowledge Base

Centralizes all domain-specific patterns (most already exist, some moved from agent):

- Dependency type classification table (label/file pattern → type → upstream source)
- Per-type breaking change signal tables
- Per-type upstream changelog fetch strategies
- Per-type impact assessment procedures (6b cross-reference logic)
- Known upstream repo mappings
- Config file location map
- Red flag keywords and scoring heuristic
- Common NO_IMPACT/HIGH_IMPACT scenario tables
- GitHub release notes format patterns

#### Processor Skill (`SKILL.md`) — Orchestrator

Update Phase 2 dispatch prompt to include the reference file path:

```
prompt: "Analyze Renovate PR #<number> in anthony-spruyt/spruyt-labs for breaking changes.
         GitHub issue: #<tracking-issue-number>
         Repository: anthony-spruyt/spruyt-labs
         Analysis patterns: .claude/skills/renovate-pr-processor/references/analysis-patterns.md
         Return your analysis in the MANDATORY output format specified in your instructions."
```

The agent's Step 0 reads this path. The processor owns the path, not the agent.

### What Changes

| File | Change |
|------|--------|
| `renovate-pr-analyzer.md` | Add Step 0; slim Steps 2/4/6/7 to reference loaded patterns; remove all baked-in domain knowledge |
| `analysis-patterns.md` | Add dependency type classification table, per-type changelog fetch strategies, and 6b cross-reference procedures (moved from agent) |
| `SKILL.md` | Add `Analysis patterns:` line to Phase 2 dispatch prompt |

### Data Flow

```
Processor (Phase 2)
  |
  |-- dispatch prompt includes: "Analysis patterns: <path>"
  |
  v
Analyzer Agent
  |
  |-- Step 0: Read(<path>) → loads knowledge base
  |-- Steps 1-7: applies loaded patterns
  |-- Steps 8-9: formats and returns results
  |
  v
Processor (Phase 5b)
  |
  |-- collects Suggested Improvements from agent outputs
  |-- writes improvements to <path>
  |
  v
Next run: agent reads improved patterns ✅
```

### Benefits

1. **Feedback loop works:** Phase 5b writes to the same file the agent reads — improvements compound
2. **Single source of truth:** No duplicate patterns that drift apart
3. **Agent stays generic:** Can analyze PRs in any repo with a different patterns file
4. **Patterns file is the only thing that grows:** Agent stays a stable size
5. **Future-proof:** Agent and skill can be synced from `claude-config` to all repos; only the patterns file is repo-specific
