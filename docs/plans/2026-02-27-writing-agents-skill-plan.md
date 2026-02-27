# Writing Agents Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a project-scoped skill that guides creating, editing, and maintaining Claude Code agents using Anthropic's official best practices.

**Architecture:** Three-file skill with progressive disclosure. SKILL.md (~200-300 lines) as the main guide, two reference files loaded on demand.

**Tech Stack:** Markdown skill files, YAML frontmatter

---

### Task 1: Create GitHub Issue

**Step 1: Create tracking issue**

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "feat(skills): add writing-agents skill for agent lifecycle management" \
  --label "enhancement" \
  --body "$(cat <<'EOF'
## Summary
Add a project-scoped skill that guides creating, editing, and maintaining Claude Code agents using Anthropic's official best practices.

## Motivation
Agent quality varies. Largest agents (qa-validator 569 lines, talos-upgrade 617 lines) exceed recommended limits. No single reference covers full agent lifecycle with current best practices. The existing plugin-dev:agent-development skill never triggers.

## Acceptance Criteria
- [ ] Skill at `.claude/skills/writing-agents/` with SKILL.md + 2 reference files
- [ ] SKILL.md under 300 lines
- [ ] Reference files with source URLs to official Anthropic docs
- [ ] qa-validator optimized as test case
- [ ] Skill triggers when working on agent files

## Affected Area
Tooling (.taskfiles/, scripts)
EOF
)"
```

**Step 2: Note the issue number — all subsequent commits must reference it.**

---

### Task 2: RED Phase — Baseline Test Without Skill

> **Purpose:** Establish what Claude does wrong when optimizing agents WITHOUT the skill present. This captures the rationalizations and failures the skill must address.

**Step 1: Run baseline test**

Spawn a subagent with this prompt (no writing-agents skill exists yet):

> "Optimize the agent at `.claude/agents/qa-validator.md` to improve token efficiency and follow best practices. The agent is 569 lines — reduce it while maintaining quality."

**Step 2: Document baseline behavior**

Record verbatim:
- What did the agent cut vs keep?
- Did it identify duplicate context from CLAUDE.md/rules?
- Did it soften emphasis markers (CRITICAL/MUST/NEVER)?
- Did it recognize over-explanations Opus doesn't need?
- Did it extract heavy content to separate files?
- What rationalizations did it use for its choices?
- What did it miss entirely?

**Step 3: Save baseline results**

Save observations to `docs/plans/2026-02-27-writing-agents-baseline.md` for comparison during GREEN phase.

**Step 4: Commit**

```bash
git add docs/plans/2026-02-27-writing-agents-baseline.md
git commit -m "docs(plans): add writing-agents skill baseline test results

Ref #<issue_number>"
```

---

### Task 3: Create Reference File - Anthropic Best Practices

**Files:**
- Create: `.claude/skills/writing-agents/references/anthropic-best-practices.md`

**Step 1: Create the reference file**

Write `references/anthropic-best-practices.md` with a table of contents at the top (file will approach 100+ lines). Each principle gets:
- A topic heading
- 2-3 sentences of actionable guidance
- Source URL

**Principles to cover (in this order):**

1. **Token Efficiency** — Context is finite. "Context rot" degrades accuracy as token count grows. Only add what Claude doesn't already know. Challenge each section: "Does this justify its token cost?"
   Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

2. **Right Altitude** — Match specificity to task fragility. High freedom (text guidance) for judgment calls where multiple approaches are valid. Low freedom (exact commands) for fragile, error-prone operations. Think: narrow bridge with cliffs = exact commands; open field = general direction.
   Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

3. **Opus 4.5/4.6 Calibration** — Opus 4.5 and Opus 4.6 are more responsive to system prompts than previous models. Instructions designed to reduce undertriggering will now cause overtriggering. Replace "CRITICAL: You MUST use this tool when..." with "Use this tool when...". Soften CRITICAL/MANDATORY/NEVER markers to normal language. Note: Sonnet 4.6 defaults to `high` effort and may also overtrigger — dial back aggressive language for all 4.5/4.6 models.
   Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

4. **Opus 4.5/4.6 Overengineering Tendency** — Opus 4.5 and Opus 4.6 tend to overengineer by creating extra files, adding unnecessary abstractions, or building in flexibility that wasn't requested. Opus 4.6 also does significantly more upfront exploration than previous models. Use targeted scope instructions: "only make changes that are directly requested." Prefer direct grep/read over spawning subagents for simple lookups.
   Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

5. **Autonomy and Safety** — Without guidance, Opus 4.6 may take actions that are hard to reverse (deleting files, force-pushing, posting to external services). Agents performing destructive or externally-visible operations should include confirmation gates. Add explicit guidance on which actions require user confirmation vs. which can proceed autonomously.
   Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

6. **Parallel Execution** — Claude 4.6 excels at parallel tool calls. Explicitly state which checks are independent to boost parallel calling to ~100%. Group independent operations and mark dependencies.
   Source: https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

7. **Progressive Disclosure** — Main file as overview pointing to detailed materials loaded on demand. Keep main body under 500 lines. Reference files one level deep only (no nested references). Include table of contents in files over 100 lines.
   Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

8. **Subagent Design** — One clear goal, input, output, and handoff rule per agent. Well-scoped tools make it easier for Claude to decide next steps. Minimize tool set overlap. Agents with vague goal definitions will over-spawn subagents on Opus 4.6 — add explicit guidance on when NOT to use subagents for focused agents.
   Sources: https://claude.com/blog/building-agents-with-the-claude-agent-sdk, https://platform.claude.com/docs/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices

9. **Tool Scoping** — Least privilege. Restrict to essential tools. Read-only agents should not have Write/Edit. Operational agents need Bash. Analysis agents need Read/Grep/Glob.
   Source: https://claude.com/blog/building-agents-with-the-claude-agent-sdk

10. **Feedback Loops** — Run validator -> fix errors -> repeat. This pattern greatly improves output quality. Structure output for the calling agent to parse and act on. Provide exact fixes, not vague guidance.
    Sources: https://claude.com/blog/building-agents-with-the-claude-agent-sdk, https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

11. **Don't Over-Explain to Opus** — Claude Opus already knows Kubernetes, YAML, Git, common tools. Remove explanations of concepts Opus understands. Focus on project-specific context it can't infer.
    Source: https://platform.claude.com/docs/en/docs/agents-and-tools/agent-skills/best-practices

12. **Don't Duplicate Inherited Context** — Agents inherit CLAUDE.md and project rules. Don't repeat secret handling rules, git conventions, or workflow constraints already in rules files. Reference them if needed, don't copy them.
    Source: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

**Note:** These reference files are library/reference content, not skill-as-discipline content. The strict TDD requirement to shape content from baseline failures applies to the SKILL.md guidance sections; the reference files document objective facts from sources and project patterns.

**Target:** ~100-150 lines. Include table of contents if file reaches 100+ lines.

**Step 2: Commit**

```bash
git add .claude/skills/writing-agents/references/anthropic-best-practices.md
git commit -m "feat(skills): add anthropic best practices reference for writing-agents skill

Ref #<issue_number>"
```

---

### Task 4: Create Reference File - Project Patterns

**Files:**
- Create: `.claude/skills/writing-agents/references/project-patterns.md`
- Read (for reference, don't modify): `.claude/agents/*.md`

**Step 1: Create the reference file**

Write `references/project-patterns.md` documenting patterns observed across the 6 existing agents in this repo. Include table of contents if file reaches 100+ lines.

**Sections:**

1. **Agent Inventory** — Table: name, lines, model, tools, memory, purpose (one line each)

2. **Model Selection** — When to use opus (complex multi-step analysis, decision-making under uncertainty) vs sonnet (focused single-domain operations, lower cost) vs haiku (quick lookups)

3. **Size Benchmarks** — Small: 100-150 lines (etcd-maintenance). Medium: 150-235 lines (cluster-validator, renovate-pr-analyzer, cnp-drop-investigator). Large: 500+ lines — overdue for optimization (qa-validator, talos-upgrade). Target: under 500 lines per Anthropic guidance, under 300 for focused agents.

4. **Memory Patterns** — When to use `memory: project`. The `known-patterns.md` table format: columns (Pattern, Count, Last Seen, Added). Auto-prune rules: remove Count=1 entries older than 30 days, never remove Count>=3.

5. **Output Format Patterns** — Common structure: verdict header (`## VERDICT: SUCCESS/ROLLBACK/BLOCKED`), evidence table, reasoning section, actionable next steps. Agents feeding orchestrators use rigid parseable formats.

6. **Handoff Patterns** — Agents post to GitHub issues via `gh issue comment`. Agents return structured output to calling skills. Agents never chain directly to each other.

7. **Description Field Patterns** — Working examples from actual agents showing: triggering conditions, when to use/not use, 2-3 `<example>` blocks with context/user/assistant/`<commentary>` format.

**Target:** ~80-120 lines.

**Step 2: Commit**

```bash
git add .claude/skills/writing-agents/references/project-patterns.md
git commit -m "feat(skills): add project patterns reference for writing-agents skill

Ref #<issue_number>"
```

---

### Task 5: Create SKILL.md

**Files:**
- Create: `.claude/skills/writing-agents/SKILL.md`

**Step 1: Write SKILL.md**

Write the main skill file with YAML frontmatter and body. Target ~200-300 lines. Verify word count stays reasonable (aim for under 2000 words — higher than the writing-skills 500-word guideline because this is a reference/technique skill with tables and structured workflows that are inherently word-dense).

**Frontmatter:**
```yaml
---
name: writing-agents
description: Guides creating, editing, and maintaining Claude Code agents using Anthropic best practices. Use when creating new agents, editing existing agent system prompts, optimizing agent token efficiency, or maintaining agent quality. Triggers on "create agent", "improve agent", "optimize agent", "agent is too long", "agent isn't working well", or when reviewing agent files in .claude/agents/.
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
Required fields: name (lowercase letters, numbers, hyphens only; max 64 chars; no reserved words "anthropic"/"claude"), description (max 1024 chars). Optional fields: model, tools, disallowedTools, permissionMode, maxTurns, skills, mcpServers, hooks, memory, background, isolation. Include format and notes for each.

**4. Description Field** (concise rules)
- Syntax: single line with `\n` for newlines, wrap in `'...'` if contains `#` after whitespace
- Write in third person (description is injected into the system prompt)
- Content: Include both what the agent does and when to use it (per official Anthropic guidance). Lead with a brief capability statement, then triggering conditions. Pattern: "Does X and Y. Use when [conditions]."
- Include 1-2 `<example>` blocks with `<commentary>` explaining why it triggers
- Anti-pattern: Do NOT expand the capability statement into a workflow summary — Claude follows description shortcut instead of reading full system prompt body. Keep "what" to a single clause, put process details in the body. (Empirically tested via writing-skills CSO.)
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
2. Write frontmatter — description with triggering conditions + examples (third person), choose model and tools (least privilege)
3. Structure system prompt — follow section order above
4. Calibrate freedom — high freedom for judgment calls, low freedom for exact commands (see `references/anthropic-best-practices.md`)
5. Size check — target under 300 lines for focused agents, under 500 max. Extract heavy reference to separate files or agent memory. Check word count (aim under 2000 words)
6. Test — run the agent against representative scenarios, verify triggering, check for overtriggering

**7. Optimization Workflow** (numbered steps)
1. Measure — count lines and words, identify largest sections
2. Remove duplicate context — check what's already in CLAUDE.md and `.claude/rules/`. Don't repeat it
3. Calibrate emphasis — replace CRITICAL/MUST/NEVER with normal language for Claude 4.5/4.6 (see `references/anthropic-best-practices.md`)
4. Remove over-explanations — delete explanations of things Opus already knows (Kubernetes, YAML, Git, etc.)
5. Extract heavy content — move large reference tables, verbose examples, or command libraries to reference files or agent memory
6. Verify — compare against `references/project-patterns.md` size benchmarks. Target: under 500 lines, under 300 for focused agents

**8. Common Mistakes** (table)

| Mistake | Fix |
|---------|-----|
| Workflow summary in description | Brief capability + triggering conditions only. Put workflow in body |
| CRITICAL/MANDATORY/NEVER overuse | Normal language. Claude 4.5/4.6 overtriggers on aggressive emphasis |
| Explaining Kubernetes/YAML/Git basics | Remove. Opus knows these |
| Copying CLAUDE.md secret rules | Remove. Agent inherits project rules |
| 500+ line system prompt | Extract reference content to files. Target <300 lines |
| All tools inherited | Restrict to what's needed (least privilege) |
| No output format specified | Add structured output template |
| No examples in description | Add 1-2 `<example>` blocks with context/user/assistant/commentary |
| Magic commands without explanation | Add brief comment explaining why (right altitude) |
| No self-improvement for high-touch agents | Add memory pattern if agent runs frequently |
| Vague agent goal encouraging subagent sprawl | One clear goal per agent. Add "when NOT to use subagents" guidance |
| No confirmation gates for destructive actions | Add explicit guidance on which actions need user confirmation |

**Step 2: Commit**

```bash
git add .claude/skills/writing-agents/SKILL.md
git commit -m "feat(skills): add writing-agents skill for agent lifecycle management

Ref #<issue_number>"
```

---

### Task 6: GREEN Phase — Test Skill Against qa-validator

> **Note:** The old rule `.claude/rules/common-agent-format.md` has already been deleted and committed separately.

**Files:**
- Modify: `.claude/agents/qa-validator.md`

**Step 1: Invoke the writing-agents skill**

Use the skill's optimization workflow against `.claude/agents/qa-validator.md`. This is the GREEN phase — can the skill guide a successful optimization that addresses the baseline failures from Task 2?

**Step 2: Apply optimizations**

Follow the skill's 6-step optimization workflow:
1. Measure current state (569 lines)
2. Identify duplicate context from CLAUDE.md/rules
3. Soften emphasis markers for Claude 4.5/4.6
4. Remove over-explanations Opus doesn't need
5. Extract heavy reference content if needed
6. Verify against size benchmarks (target: under 300 lines)

**Step 3: Compare against baseline**

Read `docs/plans/2026-02-27-writing-agents-baseline.md` and verify:
- Issues the baseline missed are now caught by the skill
- The skill's guidance addresses the specific rationalizations documented in the baseline
- If new rationalizations appear, note them for REFACTOR phase

**Step 4: Validate the optimized agent still works**

Invoke qa-validator against a recent change to verify it still produces correct validation reports.

**Step 5: Commit**

```bash
git add .claude/agents/qa-validator.md
git commit -m "refactor(agents): optimize qa-validator using writing-agents skill guidance

Ref #<issue_number>"
```

---

### Task 7: REFACTOR Phase — Close Loopholes (if needed)

**Step 1: Review GREEN phase results**

Did the skill-guided optimization miss anything? Did the agent find new rationalizations not covered by the skill?

**Step 2: Update skill if needed**

If gaps were found:
- Add explicit counters to Common Mistakes table
- Strengthen guidance in the optimization workflow
- Update reference files if patterns were missing

**Step 3: Re-test**

Run the optimization workflow again to verify the updates address the gaps.

**Step 4: Commit any skill updates**

```bash
# Only stage files that were actually modified in Step 2 — check git status first
git status
git add <only-modified-files>
git commit -m "refactor(skills): close loopholes in writing-agents skill from test results

Ref #<issue_number>"
```
