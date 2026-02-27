# Project Patterns for Agent Authoring

Patterns observed across the 6 existing agents in this repository. Use as reference when creating or optimizing agents.

## Contents

1. [Agent Inventory](#1-agent-inventory)
2. [Model Selection](#2-model-selection)
3. [Size Benchmarks](#3-size-benchmarks)
4. [Memory Patterns](#4-memory-patterns)
5. [Output Format Patterns](#5-output-format-patterns)
6. [Handoff Patterns](#6-handoff-patterns)
7. [Description Field Patterns](#7-description-field-patterns)

---

## 1. Agent Inventory

> **Maintenance:** Update this table when agents are created, deleted, or significantly modified.

| Agent | Lines | Words | Model | Tools | Memory | Purpose |
|-------|-------|-------|-------|-------|--------|---------|
| etcd-maintenance | 133 | 716 | sonnet | Bash | — | etcd health checks, defrag |
| renovate-pr-analyzer | 154 | 810 | opus | (all) | project | Analyze single Renovate PR for breaking changes |
| cluster-validator | 190 | 1,027 | opus | Bash, Read, Edit, Grep, Glob | project | Post-push cluster health validation |
| cnp-drop-investigator | 235 | 1,028 | sonnet | Bash, Read, Grep, Glob | — | Investigate Cilium network policy drops |
| qa-validator | 569 | 3,079 | opus | (all) | project | Pre-commit validation (linting, schema, docs) |
| talos-upgrade | 617 | 2,887 | opus | Bash, Read, Grep, Glob, Edit | — | Orchestrate Talos OS upgrades across nodes |

## 2. Model Selection

| Model | When to Use | Examples |
|-------|-------------|---------|
| **opus** | Complex multi-step analysis, decision-making under uncertainty, machine-parseable output, orchestration | cluster-validator, qa-validator, renovate-pr-analyzer, talos-upgrade |
| **sonnet** | Focused single-domain operations, lower token cost, pre-baked queries/templates | etcd-maintenance, cnp-drop-investigator |
| **haiku** | Quick lookups, simple classification | (none currently; consider for lightweight analysis) |

## 3. Size Benchmarks

| Category | Lines | Words | Examples |
|----------|-------|-------|----------|
| Small | 100-150 | <800 | etcd-maintenance (133/716) |
| Medium | 150-235 | 800-1,100 | cluster-validator, renovate-pr-analyzer, cnp-drop-investigator |
| Large (overdue for optimization) | 500+ | 2,800+ | qa-validator (569/3,079), talos-upgrade (617/2,887) |

**Targets:** Under 500 lines per Anthropic guidance. Under 300 lines and 2,000 words for focused agents. Extract heavy reference content to separate files or agent memory when exceeding these.

## 4. Memory Patterns

**When to use `memory: project`:** Agents that run frequently and benefit from learning across invocations (cluster-validator, renovate-pr-analyzer, qa-validator).

**`known-patterns.md` table format:**

| Column | Purpose |
|--------|---------|
| Pattern | Description of the observation |
| Count | Times observed |
| Last Seen | Most recent occurrence date |
| Added | Date first recorded |

**Auto-prune rules:** Remove Count=1 entries older than 30 days. Never remove Count >= 3. Only prune when file exceeds 50 total entries.

**Commit pattern:** `git add <specific-memory-file>` only. Never stage other files. Message: `fix(agents): update <agent>-patterns from run YYYY-MM-DD`.

## 5. Output Format Patterns

All agents use structured output templates. Common structure:

1. **Verdict header** — `## VERDICT: SUCCESS/ROLLBACK/BLOCKED/SAFE/RISKY`
2. **Evidence sections** — Tables or lists with specific findings
3. **Reasoning** — Why this verdict was reached
4. **Actionable next steps** — Exact commands or file changes needed

Agents feeding orchestrators (renovate-pr-analyzer) use rigid parseable formats. Standalone agents (etcd-maintenance) use human-readable reports.

## 6. Handoff Patterns

| Pattern | Description | Used By |
|---------|-------------|---------|
| GitHub issue comment | Post results via `gh issue comment` | cluster-validator, qa-validator, renovate-pr-analyzer |
| Structured return to caller | Return verdict + evidence for calling skill to parse | renovate-pr-analyzer, qa-validator |
| Terminal states | Named end states (SUCCESS/ROLLBACK/PARTIAL) with different templates | cluster-validator, talos-upgrade |
| Fix-and-retry loop | Return BLOCKED with exact fixes; caller applies and re-invokes | qa-validator |

Agents never chain directly to each other. Results flow through skills or the main conversation.

## 7. Description Field Patterns

**Structure:** All well-formed descriptions follow this pattern:
1. Brief capability statement (1 sentence)
2. Triggering conditions ("Use when...")
3. Anti-conditions ("When NOT to use")
4. 1-3 `<example>` blocks with `<commentary>`

**Working example (cluster-validator):**

```
Validates live cluster state after changes are pushed to main.
Checks Flux reconciliation, pod health, logs, and decides
rollback vs roll-forward on failures.

**When to use:**
- After user pushes to main branch
- When user says "pushed", "merged", or "deployed"
- After Claude merges a PR via `gh pr merge`

**When NOT to use:**
- Before git commit (use qa-validator instead)
- After pushing to feature branches

<example>
Context: User pushed changes to main.
user: "Just pushed the redis deployment"
assistant: "I'll validate the deployment with cluster-validator."
<commentary>
Push to main triggers cluster-validator.
</commentary>
</example>
```

**Anti-pattern (cnp-drop-investigator):** Flat prose description without structured when/not-to sections or examples. Harder for the routing system to match.
