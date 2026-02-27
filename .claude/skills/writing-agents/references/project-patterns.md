# Patterns for Agent Authoring

Portable patterns for creating and optimizing Claude Code agents. Derived from Anthropic guidance and field observations.

## Contents

1. [Discover Existing Patterns](#1-discover-existing-patterns)
2. [Model Selection](#2-model-selection)
3. [Size Benchmarks](#3-size-benchmarks)
4. [Memory Patterns](#4-memory-patterns)
5. [Output Format Patterns](#5-output-format-patterns)
6. [Handoff Patterns](#6-handoff-patterns)
7. [Description Field Patterns](#7-description-field-patterns)

---

## 1. Discover Existing Patterns

Before creating or optimizing an agent, scan the project's agent directory:

1. List agents: `ls .claude/agents/`
2. Read 2-3 agents to understand local conventions
3. Note: model choices, tool restrictions, description structure, output format, size

This is more reliable than a static inventory that goes stale.

## 2. Model Selection

| Model | When to Use |
|-------|-------------|
| **opus** | Complex multi-step analysis, decision-making under uncertainty, machine-parseable output, orchestration |
| **sonnet** | Focused single-domain operations, lower token cost, pre-baked queries/templates |
| **haiku** | Quick lookups, simple classification |

## 3. Size Benchmarks

| Category | Lines | Words |
|----------|-------|-------|
| Small | 100-150 | <800 |
| Medium | 150-300 | 800-1,500 |
| Large (overdue for optimization) | 500+ | 2,800+ |

**Targets:** Under 500 lines per Anthropic guidance. Under 300 lines and 2,000 words for focused agents. Cut aggressively when exceeding — remove content Opus already knows, inherited context from CLAUDE.md/rules, and verbose examples. Agents are single `.md` files; do not extract content to separate files.

## 4. Memory Patterns

**When to use `memory: project`:** Agents that run frequently and benefit from learning across invocations.

**Directory:** `.claude/agent-memory/<agent-name>/` (created automatically when `memory: project` is set). This is for runtime learning only — things the agent discovers and writes during execution. Do not pre-author static reference files here.

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

Agents feeding orchestrators use rigid parseable formats. Standalone agents use human-readable reports.

## 6. Handoff Patterns

| Pattern | Description |
|---------|-------------|
| GitHub issue comment | Post results via `gh issue comment` |
| Structured return to caller | Return verdict + evidence for calling skill to parse |
| Terminal states | Named end states (SUCCESS/ROLLBACK/PARTIAL) with different templates |
| Fix-and-retry loop | Return BLOCKED with exact fixes; caller applies and re-invokes |

Agents never chain directly to each other. Results flow through skills or the main conversation.

## 7. Description Field Patterns

**Structure:** All well-formed descriptions follow this pattern:
1. Brief capability statement (1 sentence)
2. Triggering conditions ("Use when...")
3. Anti-conditions ("When NOT to use")
4. 1-3 `<example>` blocks with `<commentary>`

**Template:**

```
<Brief capability statement — what the agent does, one sentence.>

**When to use:**
- <Triggering condition 1>
- <Triggering condition 2>

**When NOT to use:**
- <Anti-condition 1>
- <Anti-condition 2>

<example>
Context: <Situation that should trigger this agent.>
user: "<Representative user message>"
assistant: "<How the assistant should respond>"
<commentary>
<Why this triggers the agent.>
</commentary>
</example>
```

**Anti-pattern:** Flat prose description without structured when/not-to sections or examples. Harder for the routing system to match.
