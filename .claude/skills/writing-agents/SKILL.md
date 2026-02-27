---
name: writing-agents
description: Guides creating, editing, and maintaining Claude Code agents using Anthropic best practices. Use when creating new agents, editing existing agent system prompts, optimizing agent token efficiency, or maintaining agent quality. Triggers on "create agent", "improve agent", "optimize agent", "agent is too long", "agent isn't working well", or when reviewing agent files in .claude/agents/.
---

# Writing Agents

Reference guide for creating, editing, and maintaining Claude Code agents. Incorporates Anthropic's official best practices for token efficiency, prompt calibration, and progressive disclosure.

## When to Use

- Creating a new agent
- Optimizing an existing agent (too long, not performing well, overtriggering)
- Reviewing agent quality
- When NOT: skills, hooks, commands, slash commands — these are different components

## Agent Anatomy — Frontmatter

| Field | Format | Notes |
|-------|--------|-------|
| `name` | lowercase, numbers, hyphens | Max 64 chars. No reserved words ("anthropic", "claude") |
| `description` | string, max 1024 chars | What + when. See [Description Field](#description-field) below |
| `model` | `opus` / `sonnet` / `haiku` | Optional. See `references/project-patterns.md` for selection guide |
| `tools` | list of tool names | Optional. Omit for all tools. Prefer least privilege |
| `disallowedTools` | list of tool names | Optional. Block specific tools |
| `permissionMode` | string | Optional. Permission level for the agent |
| `maxTurns` | integer | Optional. Limit agentic turns |
| `skills` | list of skill names | Optional. Skills available to the agent |
| `mcpServers` | list of server names | Optional. MCP servers available |
| `hooks` | hook config object | Optional. Agent-specific hooks |
| `memory` | `project` | Optional. Enables agent memory directory |
| `background` | boolean | Optional. Run in background |
| `isolation` | `worktree` | Optional. Run in isolated worktree |

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

## Creation Workflow

1. **Define persona** — Expert identity with domain expertise, 1-2 sentences
2. **Write frontmatter** — Description with triggering conditions + examples (third person). Choose model and tools (least privilege — see `references/anthropic-best-practices.md` Section 9)
3. **Structure system prompt** — Follow section order above
4. **Calibrate freedom** — High freedom for judgment calls, low freedom for exact commands (see `references/anthropic-best-practices.md` Section 2)
5. **Size check** — Target under 300 lines / 2,000 words for focused agents, under 500 lines max. Extract heavy reference to separate files or agent memory. Run `wc -l` and `wc -w` to verify
6. **Test** — Run the agent against representative scenarios. Verify triggering. Check for overtriggering

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
| Vague agent goal encouraging subagent sprawl | One clear goal per agent. Add "when NOT to use subagents" guidance |
| No confirmation gates for destructive actions | Add explicit guidance on which actions need user confirmation |
