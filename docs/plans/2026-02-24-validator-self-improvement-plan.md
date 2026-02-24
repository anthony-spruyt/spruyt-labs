# Validator Self-Improvement Feedback Loop Implementation Plan

> **Status:** IMPLEMENTED (2026-02-24)

**Goal:** Add self-improvement feedback loops to cluster-validator and qa-validator agents so they accumulate operational knowledge across runs.

**Architecture:** Each validator uses `memory: project` to persist a `known-patterns.md` file in `.claude/agent-memory/<agent-name>/`. The first 200 lines of `MEMORY.md` are auto-loaded into the agent's context at startup. Validators self-record observations before returning verdicts. Callers (renovate-pr-processor) correct wrong verdicts by writing directly to the patterns file.

**Tech Stack:** Claude Code agents, agent memory (`memory: project`), markdown tables

---

### Task 1: Create cluster-validator agent memory with seed data

**Files:**
- Created: `.claude/agent-memory/cluster-validator/MEMORY.md`
- Created: `.claude/agent-memory/cluster-validator/known-patterns.md`
- Modified: `.claude/agents/cluster-validator.md` (added `memory: project` to frontmatter)

Seeded with patterns from recent experience (firemerge reconciliation chain issue).

---

### Task 2: Create qa-validator agent memory with empty tables

**Files:**
- Created: `.claude/agent-memory/qa-validator/MEMORY.md`
- Created: `.claude/agent-memory/qa-validator/known-patterns.md`
- Modified: `.claude/agents/qa-validator.md` (added `memory: project` to frontmatter)

Empty tables ready for the agent to populate during runs.

---

### Task 3: Add self-improvement section to cluster-validator

**Files:**
- Modified: `.claude/agents/cluster-validator.md` (appended self-improvement section before closing line)

Self-improvement section instructs the agent to:
1. Read `.claude/agent-memory/cluster-validator/known-patterns.md`
2. Compare observations against known patterns (increment count or add new row)
3. Auto-prune when exceeding 50 entries (remove Count=1 entries older than 30 days)
4. Commit changes to the patterns file only
5. Return verdict unchanged

---

### Task 4: Add self-improvement section to qa-validator

**Files:**
- Modified: `.claude/agents/qa-validator.md` (appended self-improvement section before closing line)

Same self-improvement logic as cluster-validator, adapted for QA observations (linting false positives, schema quirks, documentation gaps, failure signatures).

---

### Task 5: Add caller correction logic to renovate-pr-processor

**Files:**
- Modified: `.claude/skills/renovate-pr-processor/SKILL.md` (Step 4.5 handlers)

Updated ROLLBACK and ROLL-FORWARD handlers to write corrections to `.claude/agent-memory/cluster-validator/known-patterns.md` when the validator misdiagnoses issues or encounters new failure patterns.

---

### Design Decisions

**Why `memory: project` instead of skills:**
- `MEMORY.md` is auto-loaded into agent context at startup (first 200 lines)
- Purpose-built for agents accumulating knowledge across runs
- Version-controlled via git (`.claude/agent-memory/` is in the repo)
- No need for `skills:` preload — memory is the native mechanism

**Why not `memory: local`:**
- Project memory is version-controlled and shared
- Patterns are operational knowledge that should persist across environments
