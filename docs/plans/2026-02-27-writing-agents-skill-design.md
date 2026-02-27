# Writing Agents Skill Design

## Problem

Agent quality in this project varies significantly. The qa-validator (569 lines) and talos-upgrade (617 lines) exceed Anthropic's recommended 500-line limit, contain duplicate context from CLAUDE.md rules, and use aggressive emphasis markers (CRITICAL/MANDATORY/NEVER) that cause overtriggering on Claude 4.6. Meanwhile, the existing `plugin-dev:agent-development` skill never triggers for agent work in this project, and the `common-agent-format.md` rule provides a structural template but no optimization or maintenance guidance.

There is no single reference that covers the full agent lifecycle (create, edit, maintain) with Anthropic's official best practices applied.

## Solution

A project-scoped skill at `.claude/skills/writing-agents/` with progressive disclosure:

```
writing-agents/
├── SKILL.md                          # Main guide (~200-300 lines)
└── references/
    ├── anthropic-best-practices.md   # Distilled official guidance with source URLs
    └── project-patterns.md           # Patterns from this repo's existing agents
```

Delete `.claude/rules/common-agent-format.md` — its content is absorbed into the skill. The rule's auto-loading advantage is outweighed by drift risk from two sources of truth.

## SKILL.md Structure

### Frontmatter

- **name:** `writing-agents`
- **description:** Triggers on creating, editing, optimizing, maintaining agents, and when working with `.claude/agents/` files.

### Body Sections

1. **Overview** — What this skill is (1-2 sentences)
2. **When to Use / When NOT to Use** — Agent work vs skills/hooks/commands
3. **Agent Anatomy** — Frontmatter fields table (required + optional), absorbed from the deleted rule
4. **Description Field** — Syntax, content rules, anti-pattern about workflow summaries in descriptions
5. **System Prompt Structure** — Canonical section order for this project's agents
6. **Creation Workflow** — 6 steps: define persona, write frontmatter, structure prompt, calibrate freedom, choose model/tools, test
7. **Optimization Workflow** — 6 steps: measure, apply best practices (ref file), remove duplicates, calibrate for 4.6, extract heavy content, verify against patterns (ref file)
8. **Common Mistakes** — Anti-pattern table with fixes

## Reference Files

### `references/anthropic-best-practices.md` (~100-150 lines)

Distilled from 4 official Anthropic sources:

| Topic | Key Principle |
|-------|--------------|
| Token efficiency | Context is finite, "context rot" degrades accuracy |
| Right altitude | Match specificity to task fragility |
| Claude 4.6 calibration | Soften CRITICAL/MUST/NEVER emphasis |
| Parallel execution | Explicitly state independent checks |
| Progressive disclosure | Overview in main file, heavy content in references |
| Subagent design | One clear goal, input, output, handoff per agent |
| Tool scoping | Least privilege — restrict to essential tools |
| Feedback loops | Run -> fix -> repeat pattern |
| Over-explaining to Opus | Remove explanations of things Opus already knows |
| Duplicate context | Don't repeat inherited CLAUDE.md/rules content |

Each entry includes 2-3 sentences of guidance and a source URL.

**Sources:**
- [Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Prompting Best Practices - Claude 4](https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Building Agents with Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)
- [Skill Authoring Best Practices](https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices) (bundled in superpowers plugin)

### `references/project-patterns.md` (~80-120 lines)

Derived from this repo's 6 existing agents:

- **Model selection:** opus for complex analysis, sonnet for focused operations
- **Memory patterns:** `known-patterns.md` table format (pattern, count, last-seen, added)
- **Size benchmarks:** Small (100-150 lines), medium (150-200), large (200-250)
- **Output formats:** Verdict headers, evidence tables, reasoning sections
- **Handoff patterns:** Structured results for calling skills/agents
- **GitHub integration:** Results posted as issue comments via `gh` CLI

## Deletions

- `.claude/rules/common-agent-format.md` — absorbed into skill

## Test Plan

Use the qa-validator agent as the test case:
1. Invoke the skill for optimization
2. Verify it identifies the key issues (token bloat, duplicate context, aggressive emphasis)
3. Apply the skill's optimization workflow
4. Compare before/after line count and quality

## Success Criteria

- Skill triggers when working on agent files (without needing to be explicitly requested)
- SKILL.md stays under 300 lines
- Reference files provide actionable guidance with source citations
- qa-validator can be improved using only the skill's guidance
