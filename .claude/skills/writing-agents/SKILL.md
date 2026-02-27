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

Not every agent needs all sections. Small focused agents (etcd-maintenance style) may only need Persona, Workflow, Rules, and Output Format.

**Output format:** Agents feeding orchestrators use rigid parseable formats. Standalone agents use human-readable reports. See `references/project-patterns.md` Section 5.

**Handoff patterns:** Choose from: GitHub issue comment, structured return to caller, terminal states (SUCCESS/ROLLBACK/PARTIAL), or fix-and-retry loop. See `references/project-patterns.md` Section 6.

## Creation Workflow

1. **Define persona** — Expert identity with domain expertise, 1-2 sentences
2. **Write frontmatter** — Description with triggering conditions + examples (third person). Choose model and tools (least privilege — see `references/anthropic-best-practices.md` Section 9)
3. **Structure system prompt** — Follow section order above
4. **Calibrate freedom** — High freedom for judgment calls, low freedom for exact commands (see `references/anthropic-best-practices.md` Section 2)
5. **Scope-limit Opus** — For agents that make modifications, add "Only make changes directly requested." Prefer direct Grep/Read over spawning subagents for simple lookups (see `references/anthropic-best-practices.md` Section 4)
6. **Safety gates** — Identify destructive or externally-visible operations. Add confirmation gates for irreversible actions. For hard-stop gates, use strong language despite the general softening rule (e.g., "stop immediately with BLOCKED"). Add "stop on error" termination conditions for sequential multi-step workflows
7. **Size check** — Target under 300 lines / 2,000 words for focused agents, under 500 lines max. Extract heavy reference to separate files or agent memory. Run `wc -l` and `wc -w` to verify
8. **Test** — Run the agent against representative scenarios. Verify triggering. Check for overtriggering

## Optimization Workflow

1. **Measure** — Count lines (`wc -l`) and words (`wc -w`). Identify largest sections
2. **Remove duplicate context** — Check what's already in CLAUDE.md and `.claude/rules/`. Agents inherit these automatically. Don't repeat them — reference if needed ("follow inherited rules for X")
3. **Calibrate emphasis** — Replace CRITICAL/MUST/NEVER with normal language for Claude 4.5/4.6. These models overtrigger on aggressive emphasis (see `references/anthropic-best-practices.md` Section 3). Reserve strong language only for true safety gates (e.g., "never expose secrets")
4. **Remove over-explanations** — Delete explanations of things Opus already knows (Kubernetes, YAML, Git, bash, common tools). Focus on project-specific context it can't infer (see `references/anthropic-best-practices.md` Section 11)
5. **Extract heavy content** — Move large reference tables, verbose examples, or command libraries to reference files or agent memory. Keep the main prompt as a workflow guide, not an encyclopedia
6. **Verify** — Compare against `references/project-patterns.md` size benchmarks. Target: under 500 lines, under 300 for focused agents, under 2,000 words

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Workflow summary in description | Brief capability + triggering conditions only. Put workflow in body |
| CRITICAL/MANDATORY/NEVER overuse | Normal language. Claude 4.5/4.6 overtriggers on aggressive emphasis |
| Explaining Kubernetes/YAML/Git basics | Remove. Opus knows these |
| Copying CLAUDE.md secret rules | Remove. Agent inherits project rules |
| 500+ line system prompt | Extract reference content to files. Target < 300 lines |
| All tools inherited | Restrict to what's needed (least privilege) |
| No output format specified | Add structured output template |
| No examples in description | Add 1-2 `<example>` blocks with context/user/assistant/commentary |
| Magic commands without explanation | Add brief comment explaining why (right altitude) |
| No self-improvement for high-touch agents | Add memory pattern if agent runs frequently |
| Vague scope enabling unnecessary subagent spawning | Add "Only make changes directly requested." Prefer Grep/Read over subagents for lookups |
| Multi-goal agent | Split into focused agents. One clear goal, input, output per agent |
| No confirmation gates for destructive actions | Add explicit guidance on which actions need user confirmation |
| Independent checks run sequentially | Mark parallel groups: "Run in parallel: [list]. After those pass: [list]" (see `references/anthropic-best-practices.md` Section 6) |
| No feedback loop for validation agents | Add validator -> fix -> retry pattern with structured output (file paths, line numbers, exact fixes) |
