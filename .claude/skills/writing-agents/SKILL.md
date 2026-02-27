---
name: writing-agents
description: Use when creating new agents, editing existing agent system prompts, optimizing agent token efficiency, or maintaining agent quality. Applies when agent is too long, not performing well, overtriggering, or when reviewing agent files in .claude/agents/. Does not apply to skills, hooks, commands, or slash commands.
---

# Writing Agents

## Overview

Patterns and workflows for writing effective, token-efficient agent system prompts.

## Quick Reference

| Task | Reference |
|------|-----------|
| Frontmatter fields | `references/agent-frontmatter.md` |
| Description examples | `references/project-patterns.md` Section 7 |
| Model selection | `references/project-patterns.md` Section 2 |
| Size targets | `references/project-patterns.md` Section 3 |
| Memory patterns | `references/project-patterns.md` Section 4 |
| Output format patterns | `references/project-patterns.md` Section 5 |
| Handoff patterns | `references/project-patterns.md` Section 6 |
| Emphasis calibration | `references/anthropic-best-practices.md` Section 3 |
| Parallel execution | `references/anthropic-best-practices.md` Section 6 |
| Common mistakes | `references/common-mistakes.md` |

## Description Field

**Syntax:** Single line with `\n` for newlines. Wrap in `'...'` if contains `#` after whitespace.

**Write in third person** — the description is injected into the system prompt by the routing system.

**Content pattern:** Brief capability statement (1 clause), then triggering conditions. Do NOT expand the capability statement into a workflow summary — Claude follows the description shortcut instead of reading the full system prompt body. Keep "what" to a single clause, put process details in the body.

**Include:**
- "Use when..." / "When to use" conditions
- "When NOT to use" anti-conditions
- 1-2 `<example>` blocks with `<commentary>` explaining why it triggers

See `references/project-patterns.md` Section 7 for working examples.

## System Prompt Structure

Canonical section order for this project:

1. **Persona/Role** — Expert identity with domain expertise, 1-2 sentences
2. **Core Responsibilities** — Numbered, 3-5 items
3. **Mandatory Gates** — Issue requirements, input validation
4. **Classification/Detection** — Change-type analysis, input categorization
5. **Workflow Steps** — The main process
6. **Output Format** — Structured template (verdict header, evidence, next steps)
7. **Handoff Protocol** — How results return to caller
8. **Critical Rules** — Numbered constraints
9. **Self-Improvement** — If using memory (see `references/project-patterns.md` Section 4)

Not every agent needs all sections. Small focused agents may only need Persona, Workflow, Rules, and Output Format.

**Output format:** Agents feeding orchestrators use rigid parseable formats. Standalone agents use human-readable reports. See `references/project-patterns.md` Section 5.

**Handoff patterns:** Choose from: GitHub issue comment, structured return to caller, terminal states (SUCCESS/ROLLBACK/PARTIAL), or fix-and-retry loop. See `references/project-patterns.md` Section 6.

## Creation Workflow

1. **Define persona** — See Persona/Role in System Prompt Structure above
2. **Write frontmatter** — Description with triggering conditions + examples (third person). Choose model and tools (least privilege — see `references/anthropic-best-practices.md` Section 9)
3. **Structure system prompt** — Follow section order above
4. **Calibrate freedom** — High freedom for judgment calls, low freedom for exact commands (see `references/anthropic-best-practices.md` Section 2)
5. **Scope-limit Opus** — For agents that make modifications, add "Only make changes directly requested." Prefer direct Grep/Read over spawning subagents for simple lookups (see `references/anthropic-best-practices.md` Section 4)
6. **Safety gates** — Identify destructive or externally-visible operations. Add confirmation gates for irreversible actions. For hard-stop gates, use strong language despite the general softening rule (e.g., "stop immediately with BLOCKED"). Add "stop on error" termination conditions for sequential multi-step workflows
7. **Size check** — Target under 300 lines / 2,000 words for focused agents, under 500 lines max. Agents are single `.md` files in `.claude/agents/` — cut content rather than extracting. Run `wc -l` and `wc -w` to verify
8. **Test** — Run the agent against representative scenarios. Verify triggering. Check for overtriggering

## Optimization Workflow

Use sub-agents for each phase. Fresh context prevents sunk cost bias and keeps each step focused.

### Phase 1: Optimize (sub-agent)

Dispatch an optimization sub-agent. Provide it with: the agent file path, this skill, and all inherited context files (CLAUDE.md, `.claude/rules/*`). The sub-agent follows these steps:

1. **Measure** — Count lines (`wc -l`) and words (`wc -w`). Identify largest sections
2. **Fix description field** — Must comply with the Description Field section of this skill:
   - Under 1024 chars (measure and verify). If over: trim to 1-2 examples, remove workflow summaries, shorten dialogue
   - No workflow summary (lines like "Handoff flow: X → Y → Z"). Only capability + triggering conditions
   - Every `<example>` must contain `<commentary>` explaining why it triggers. Add if missing
   - Max 2 `<example>` blocks
   - Must have "When to use" and "When NOT to use" sections
3. **Remove inherited context** — Read CLAUDE.md and every `.claude/rules/` file. Search the agent for duplicated content. Common: secret handling, git staging, research priority, domain substitution. Replace with single-line references (e.g., "Follow inherited secret handling rules")
4. **Calibrate emphasis** — Soften CRITICAL/MUST/NEVER/FORBIDDEN/MANDATORY (see `references/anthropic-best-practices.md` Section 3). Remove explanations Opus knows (Section 12). **Safety gates** (hard stops preventing data loss, secret exposure, skipping required inputs) keep strong language. **Operational preferences** (tool choice, workflow ordering, style) use normal language — no bold, no CRITICAL, no blockquote emphasis
5. **Cut aggressively** — Remove Opus-known content, inherited context, verbose examples. Agents are single files; do not extract. **Keep:** domain-specific commands with non-obvious flags, exact commit/git commands in self-improvement, behavioral anchors preventing shallow execution
6. **Verify frontmatter** — All original fields must survive (`name`, `description`, `model`, `memory`, `tools`). Missing `tools` silently grants all tools

### Phase 2: Validate (two parallel sub-agents)

Dispatch two fresh sub-agents (no shared context with the optimizer). Both read: the optimized file, the original (via `git show <pre-optimization-ref>:<path>`), inherited context files, and this skill. Run in parallel:

- **Structural review**: Frontmatter fields survived. Description under 1024 chars, no workflow summary, examples have `<commentary>`, max 2 examples. System prompt sections present. Emphasis calibrated (strong only on safety gates). Output format and handoff protocol present. Return PASS/FAIL with specific issues and exact fixes.
- **Effectiveness review**: Compare for lost domain-specific knowledge not in inherited context and that Opus wouldn't know. All workflow steps still represented. Domain commands with non-obvious flags preserved. Classify cuts as SAFE/RISKY/LOST. Return EFFECTIVE/DEGRADED/BROKEN.

### Phase 3: Fix loop

If either validator returns FAIL/DEGRADED: dispatch a fix sub-agent with the specific issues and exact fixes. Then re-run Phase 2. Repeat until both validators return PASS + EFFECTIVE.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Workflow summary in description | Brief capability + triggering conditions only. Put workflow in body |
| CRITICAL/MANDATORY/NEVER overuse | Normal language. Claude 4.5/4.6 overtriggers on aggressive emphasis |
| 500+ line system prompt | Cut aggressively — remove what Opus knows. Target < 300 lines |
| No output format specified | Add structured output template |
| No examples in description | Add 1-2 `<example>` blocks with context/user/assistant/commentary |
| See full list | `references/common-mistakes.md` |
