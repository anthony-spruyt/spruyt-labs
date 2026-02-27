# Writing Agents Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a project-scoped skill that guides creating, editing, and maintaining Claude Code agents using Anthropic's official best practices.

**Architecture:** Three-file skill with progressive disclosure. SKILL.md (~200-300 lines) as the main guide, two reference files loaded on demand. Replaces the existing `common-agent-format.md` rule.

**Tech Stack:** Markdown skill files, YAML frontmatter

---

### Task 1: Create Reference File - Anthropic Best Practices

**Files:**
- Create: `.claude/skills/writing-agents/references/anthropic-best-practices.md`

**Step 1: Create the reference file**

Write `references/anthropic-best-practices.md` containing the 10 distilled principles from official Anthropic sources. Each principle gets:
- A topic heading
- 2-3 sentences of actionable guidance
- Source URL

**Topics to cover (in this order):**

1. **Token Efficiency** — Context is finite. "Context rot" degrades accuracy as token count grows. Only add what Claude doesn't already know. Challenge each section: "Does this justify its token cost?"
   Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

2. **Right Altitude** — Match specificity to task fragility. High freedom (text guidance) for judgment calls where multiple approaches are valid. Low freedom (exact commands) for fragile, error-prone operations. Think: narrow bridge with cliffs = exact commands; open field = general direction.
   Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

3. **Claude 4.6 Calibration** — Opus 4.6 is more responsive to system prompts than previous models. Instructions designed to reduce undertriggering will now cause overtriggering. Replace "CRITICAL: You MUST use this tool when..." with "Use this tool when...". Soften CRITICAL/MANDATORY/NEVER markers to normal language.
   Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

4. **Parallel Execution** — Claude 4.6 excels at parallel tool calls. Explicitly state which checks are independent to boost parallel calling to ~100%. Group independent operations and mark dependencies.
   Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

5. **Progressive Disclosure** — Main file as overview pointing to detailed materials loaded on demand. Keep main body under 500 lines. Reference files one level deep only (no nested references). Include table of contents in files over 100 lines.
   Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

6. **Subagent Design** — One clear goal, input, output, and handoff rule per agent. Well-scoped tools make it easier for Claude to decide next steps. Minimize tool set overlap.
   Source: https://claude.com/blog/building-agents-with-the-claude-agent-sdk

7. **Tool Scoping** — Least privilege. Restrict to essential tools. Read-only agents should not have Write/Edit. Operational agents need Bash. Analysis agents need Read/Grep/Glob.
   Source: https://claude.com/blog/building-agents-with-the-claude-agent-sdk

8. **Feedback Loops** — Run validator -> fix errors -> repeat. This pattern greatly improves output quality. Structure output for the calling agent to parse and act on. Provide exact fixes, not vague guidance.
   Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

9. **Don't Over-Explain to Opus** — Claude Opus already knows Kubernetes, YAML, Git, common tools. Remove explanations of concepts Opus understands. Focus on project-specific context it can't infer.
   Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

10. **Don't Duplicate Inherited Context** — Agents inherit CLAUDE.md and project rules. Don't repeat secret handling rules, git conventions, or workflow constraints already in rules files. Reference them if needed, don't copy them.
    Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

**Target:** ~100-150 lines.

**Step 2: Commit**

```bash
git add .claude/skills/writing-agents/references/anthropic-best-practices.md
git commit -m "feat(skills): add anthropic best practices reference for writing-agents skill"
```

---

### Task 2: Create Reference File - Project Patterns

**Files:**
- Create: `.claude/skills/writing-agents/references/project-patterns.md`
- Read (for reference, don't modify): `.claude/agents/*.md`

**Step 1: Create the reference file**

Write `references/project-patterns.md` documenting patterns observed across the 6 existing agents in this repo. Structure:

**Sections:**

1. **Agent Inventory** — Table: name, lines, model, tools, memory, purpose (one line each)

2. **Model Selection** — When to use opus (complex multi-step analysis, decision-making under uncertainty) vs sonnet (focused single-domain operations, lower cost) vs haiku (quick lookups)

3. **Size Benchmarks** — Small: 100-150 lines (etcd-maintenance). Medium: 150-235 lines (cluster-validator, renovate-pr-analyzer, cnp-drop-investigator). Large: 500+ lines — considered overdue for optimization (qa-validator, talos-upgrade). Target: under 500 lines per Anthropic guidance.

4. **Memory Patterns** — When to use `memory: project`. The `known-patterns.md` table format: columns (Pattern, Count, Last Seen, Added). Auto-prune rules: remove Count=1 entries older than 30 days, never remove Count>=3.

5. **Output Format Patterns** — Common structure: verdict header (`## VERDICT: SUCCESS/ROLLBACK/BLOCKED`), evidence table, reasoning section, actionable next steps. Agents feeding orchestrators use rigid parseable formats.

6. **Handoff Patterns** — Agents post to GitHub issues via `gh issue comment`. Agents return structured output to calling skills. Agents never chain directly to each other.

7. **Description Field Patterns** — Working examples from actual agents showing: one-sentence summary, when to use/not use, 2-3 `<example>` blocks with context/user/assistant format.

**Target:** ~80-120 lines.

**Step 2: Commit**

```bash
git add .claude/skills/writing-agents/references/project-patterns.md
git commit -m "feat(skills): add project patterns reference for writing-agents skill"
```

---

### Task 3: Create SKILL.md

**Files:**
- Create: `.claude/skills/writing-agents/SKILL.md`
- Read (for absorption): `.claude/rules/common-agent-format.md`

**Step 1: Write SKILL.md**

Write the main skill file with YAML frontmatter and body. Target ~200-300 lines.

**Frontmatter:**
```yaml
---
name: writing-agents
description: Use when creating new agents, editing existing agent system prompts, optimizing agent token efficiency, or maintaining agent quality. Triggers on "create agent", "improve agent", "optimize agent", "agent is too long", "agent isn't working well", or when reviewing agent files in .claude/agents/.
---
```

**Body sections (in order):**

**1. Overview** (2-3 lines)
Reference guide for creating, editing, and maintaining Claude Code agents. Incorporates Anthropic's official best practices for token efficiency, prompt calibration, and progressive disclosure.

**2. When to Use** (bullet list)
- Creating a new agent
- Optimizing an existing agent (too long, not performing well, overtriggering)
- Reviewing agent quality
- When NOT: skills, hooks, commands, slash commands (different components)

**3. Agent Anatomy — Frontmatter** (table)
Absorb the frontmatter tables from `common-agent-format.md`. Required fields: name, description. Optional fields: model, tools, disallowedTools, permissionMode, maxTurns, skills, mcpServers, hooks, memory, background, isolation.

**4. Description Field** (concise rules)
- Syntax: single line with `\n` for newlines, wrap in `'...'` if contains `#` after whitespace
- Content: one-sentence summary, when to use/not use, 1-2 `<example>` blocks with `<commentary>`
- Anti-pattern: Do NOT summarize workflow in description — Claude follows description shortcut instead of reading body
- See `references/project-patterns.md` for working examples

**5. System Prompt Structure** (ordered list)
Canonical section order for this project:
1. Persona/Role (1-2 sentences)
2. Core Responsibilities (numbered, 3-5 items)
3. Mandatory Gates (issue requirements, input validation)
4. Classification/Detection (change-type, input analysis)
5. Workflow Steps (the main process)
6. Output Format (structured template)
7. Handoff Protocol (how results return to caller)
8. Critical Rules (numbered constraints)
9. Self-Improvement (if using memory)

**6. Creation Workflow** (numbered steps)
1. Define persona — expert identity with domain expertise, 1-2 sentences
2. Write frontmatter — description with triggers + examples, choose model and tools (least privilege)
3. Structure system prompt — follow section order above
4. Calibrate freedom — high freedom for judgment calls, low freedom for exact commands (see `references/anthropic-best-practices.md`)
5. Size check — target under 300 lines for focused agents, under 500 max. Extract heavy reference to separate files or agent memory
6. Test — run the agent against representative scenarios, verify triggering, check for overtriggering

**7. Optimization Workflow** (numbered steps)
1. Measure — count lines, identify largest sections
2. Remove duplicate context — check what's already in CLAUDE.md and `.claude/rules/`. Don't repeat it
3. Calibrate emphasis — replace CRITICAL/MUST/NEVER with normal language for Claude 4.6 (see `references/anthropic-best-practices.md`)
4. Remove over-explanations — delete explanations of things Opus already knows (Kubernetes, YAML, Git, etc.)
5. Extract heavy content — move large reference tables, verbose examples, or command libraries to reference files or agent memory
6. Verify — compare against `references/project-patterns.md` size benchmarks. Target: under 500 lines

**8. Common Mistakes** (table)

| Mistake | Fix |
|---------|-----|
| Workflow summary in description | Move to body. Description = triggers only |
| CRITICAL/MANDATORY/NEVER overuse | Normal language. Claude 4.6 overtriggers on aggressive emphasis |
| Explaining Kubernetes/YAML/Git basics | Remove. Opus knows these |
| Copying CLAUDE.md secret rules | Remove. Agent inherits project rules |
| 500+ line system prompt | Extract reference content to files. Target <300 lines |
| All tools inherited | Restrict to what's needed (least privilege) |
| No output format specified | Add structured output template |
| No examples in description | Add 1-2 `<example>` blocks with context/user/assistant |
| Magic commands without explanation | Add brief comment explaining why (right altitude) |
| No self-improvement for high-touch agents | Add memory pattern if agent runs frequently |

**Step 2: Commit**

```bash
git add .claude/skills/writing-agents/SKILL.md
git commit -m "feat(skills): add writing-agents skill for agent lifecycle management"
```

---

### Task 4: Delete the Old Rule

**Files:**
- Delete: `.claude/rules/common-agent-format.md`

**Step 1: Verify skill covers all rule content**

Read both files side by side. Confirm every useful piece of the rule is represented in the skill (frontmatter table, description syntax, template pattern, best practices).

**Step 2: Delete the rule file**

```bash
rm .claude/rules/common-agent-format.md
```

**Step 3: Commit**

```bash
git add .claude/rules/common-agent-format.md
git commit -m "chore(rules): remove common-agent-format rule, absorbed into writing-agents skill"
```

---

### Task 5: Test with qa-validator optimization

**Files:**
- Modify: `.claude/agents/qa-validator.md`

**Step 1: Invoke the writing-agents skill**

Use the skill's optimization workflow against `.claude/agents/qa-validator.md`. This is the real test — can the skill guide a successful optimization?

**Step 2: Apply optimizations**

Follow the skill's 6-step optimization workflow:
1. Measure current state (569 lines)
2. Identify duplicate context from CLAUDE.md/rules
3. Soften emphasis markers for Claude 4.6
4. Remove over-explanations Opus doesn't need
5. Extract heavy reference content if needed
6. Verify against size benchmarks (target: under 300 lines)

**Step 3: Validate the optimized agent still works**

Invoke qa-validator against a recent change to verify it still produces correct validation reports.

**Step 4: Commit**

```bash
git add .claude/agents/qa-validator.md
git commit -m "refactor(agents): optimize qa-validator using writing-agents skill guidance"
```

---

### Task 6: Create GitHub Issue

**Step 1: Create tracking issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(skills): add writing-agents skill for agent lifecycle management" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Add a project-scoped skill that guides creating, editing, and maintaining Claude Code agents using Anthropic's official best practices.

## Motivation
Agent quality varies. Largest agents (qa-validator 569 lines, talos-upgrade 617 lines) exceed recommended limits. No single reference covers full agent lifecycle with current best practices. The existing plugin-dev:agent-development skill never triggers. The common-agent-format rule provides structure but no optimization guidance.

## Acceptance Criteria
- [ ] Skill at `.claude/skills/writing-agents/` with SKILL.md + 2 reference files
- [ ] SKILL.md under 300 lines
- [ ] Reference files with source URLs to official Anthropic docs
- [ ] `.claude/rules/common-agent-format.md` deleted (absorbed into skill)
- [ ] qa-validator optimized as test case
- [ ] Skill triggers when working on agent files

## Affected Area
Tooling (.taskfiles/, scripts)
EOF
)"
```

**Note:** Create this issue FIRST, before starting Task 1, to comply with the issue-first workflow. All commits should reference the issue number.
