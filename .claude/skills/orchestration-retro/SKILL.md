---
name: orchestration-retro
description: >
  Review how helper delegation went from the Claude Code session logs. Use when the owner asks for an orchestration retro or to review
  how helpers or delegation went, and about monthly.
---

# Orchestration Retro

Report to the owner only; never post it to GitHub.

## 1. Run the report

```bash
.claude/skills/orchestration-retro/retro.sh --since "$(date -d '30 days ago' +%F)"
```

Use another `--since` date if the owner names a window. The script is read-only and prints helper counts and output tokens per agent type and model, general-purpose helpers that ran on Opus, review verdicts, PRs with 3 or more helper runs, and non-None `### Agent Definition Feedback`.

## 2. Read it

- Routing: general-purpose helpers on Opus mean a brief should have named `pr-builder`, `pr-reviewer` or `chore-runner`, or a rule or agent description is unclear.
- Rework: PRs with many runs point to briefs that missed something.
- Feedback: entries not yet applied to the agent file.

## 3. Propose changes

Propose up to 5 one-line changes to `.claude/rules/orchestration.md` or a `.claude/agents/*.md` file. Tie each to the report line that supports it.

Change nothing until the owner approves.
