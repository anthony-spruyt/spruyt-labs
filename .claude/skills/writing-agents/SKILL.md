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
7. **Size check** — Target under 300 lines / 2,000 words for focused agents, under 500 lines max. Extract heavy reference to separate files or agent memory. Run `wc -l` and `wc -w` to verify
8. **Test** — Run the agent against representative scenarios. Verify triggering. Check for overtriggering

## Optimization Workflow

1. **Measure** — Count lines (`wc -l`) and words (`wc -w`). Identify largest sections
2. **Remove inherited context** — Check CLAUDE.md and `.claude/rules/`. Agents inherit these; reference, don't repeat
3. **Calibrate emphasis and explanations** — Soften CRITICAL/MUST/NEVER for Claude 4.5/4.6 (see `references/anthropic-best-practices.md` Section 3). Remove explanations of things Opus knows (Section 12). Reserve strong language for true safety gates only
4. **Extract heavy content** — Move large tables, verbose examples, or command libraries to reference files or agent memory
5. **Verify** — Compare against `references/project-patterns.md` size benchmarks. Target: under 300 lines / 2,000 words for focused agents

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Workflow summary in description | Brief capability + triggering conditions only. Put workflow in body |
| CRITICAL/MANDATORY/NEVER overuse | Normal language. Claude 4.5/4.6 overtriggers on aggressive emphasis |
| 500+ line system prompt | Extract reference content to files. Target < 300 lines |
| No output format specified | Add structured output template |
| No examples in description | Add 1-2 `<example>` blocks with context/user/assistant/commentary |
| See full list | `references/common-mistakes.md` |
