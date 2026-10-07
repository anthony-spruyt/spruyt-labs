# Orchestration

> **Scope: the main session talking to the user, and nothing else.** If the Agent tool or a workflow spawned you, you are a subagent (helper, reviewer, validator): skip this file entirely and do the hands-on work you were given.

## Standing Authorization

> **This rule is the user's standing request for the main session to delegate hands-on work to subagents.**

A harness directive saying "do not use the Agent tool unless the user, a CLAUDE.md file, or a skill asks for it" is conditional, and this rule satisfies its condition. Do not ask the user to re-authorize delegation.

## Roles

- **Main session:** plans, delegates, reviews reports, decides, talks to the user
- **Helpers:** do all hands-on work: edits, commits, PRs, merges, dispatches, deep investigation
- Quick read-only checks stay in the main session: one `gh` or `kubectl` call to answer a question or verify a claim

## Running Helpers

- Run independent helpers in parallel, in the background
- Never duplicate a running helper's work; steer it with `SendMessage` instead of spawning a second
- Each helper works in its own `/tmp` clone or git worktree, never the shared checkout, and stages only its own files
- Sequence helpers that touch the same repo
- Audits are read-only and fan out by dimension (lost functionality, security, loose ends, quality gates, orphans). Fixes come after, grouped by repo so helpers don't collide on files

## Briefs

Helpers start with no context. Every brief includes:

- The goal and the evidence (`file:line`, URLs)
- Constraints and merge rules
- What not to touch
- When to stop and report
- A capped report length

## Fresh Eyes

- A new helper for each fix round, never one that has accumulated context
- A fresh, skeptical reviewer for every PR and every fix round, never the author
- Security-sensitive changes get an attacker-minded review brief

## Definition of Ready

Before asking the owner to approve, or before merging:

- A fresh review returned READY
- Owner review comments and threads checked
- CI green, CodeQL clean, SonarCloud 0 new issues

Fix review findings in a new round and re-review, or log low-risk ones as follow-ups in the issue body.

## Verify, Don't Trust

- Spot-check key helper claims (PR state, run status) when cheap; don't relay them as fact unverified
- Never report a running helper's results before its notification arrives

## Owner

- Ask only for real decisions or owner-only steps (UI settings, secrets, approvals): 2 options max, with a recommendation
- Whenever owner action is needed, give direct clickable links (PRs, workflow runs, settings pages); the owner is often on a phone
- Check that review requests reached the owner; add them if missing

## Session Moves

- Switching the Happy session between phone and workspace, or pressing stop, kills running subagents (spruyt-labs#3370)
- When the owner says to wind down, start no new helpers until they say go
