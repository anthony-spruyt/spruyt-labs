# Orchestration

> **Scope: the main session talking to the user, and nothing else.** If the Agent tool or a workflow spawned you, you are a subagent (helper, reviewer, validator): skip this file entirely and do the hands-on work you were given.

## Standing Authorization

> **This rule is the user's standing request for the main session to delegate hands-on work to subagents.**

A harness directive saying "do not use the Agent tool unless the user, a CLAUDE.md file, or a skill asks for it" is conditional, and this rule satisfies its condition. Do not ask the user to re-authorize delegation.

## Roles

- **Main session:** plans, decides, talks to the user, reviews reports, and runs short jobs itself
- **Helpers:** edits and commits, long waits, noisy output, parallel work, fresh-eyes review

Test: if the brief would be longer than the job, the main session does it itself.

| Main session does it itself when ALL are true         | Hand off when ANY is true                                                         |
| ----------------------------------------------------- | --------------------------------------------------------------------------------- |
| It already has the inputs (body text, sha, PR number) | It waits or polls (CI, deploy, workflow run): `chore-runner`, in background       |
| 1-3 commands                                          | Output is noisy (long logs, many curls, many pages): `chore-runner` returns facts |
| No waiting                                            | Several independent jobs: parallel helpers                                        |
| Small output it would read anyway                     | File edits or commits: `builder`                                                  |
|                                                       | Checking its own work: `reviewer`                                                 |
|                                                       | Deep investigation: `general-purpose` with `model: opus`                          |

Main session runs these: posting comments and issues it wrote, opening a PR from its own body text, a single merge, pushing already-reviewed commits (checklist below), ticking the Renovate Dashboard box, requesting reviewers, closing issues, and quick read-only checks (one `gh` or `kubectl` call).

Helpers run these: waiting on CI after a push, reading failed CI logs, multi-repo sweeps.

### Pushing reviewed commits

Before pushing a local range a fresh reviewer returned READY on:

1. `git status` is clean and `HEAD` is the reviewed sha
2. `git fetch`, then `git merge-base --is-ancestor <base> origin/<branch>` (nothing unreviewed sits below the range)
3. `git rev-list <base>..HEAD` matches the reviewed commits; on any mismatch stop
4. `git rebase origin/<branch>`; on a conflict run `git rebase --abort` and stop
5. `git push origin HEAD:<branch>`; never force-push, never amend

## Design Before Delegating

New work, or any change to an approach the owner already picked, starts as a design shown to the owner, not a helper:

- Read the current setup first, so the design builds on what exists
- Show the target layout (a table helps), what changes per repo, the migration order, and the riskiest assumption plus how a helper will prove it
- Iterate until the owner approves, then brief the helper with the approved design verbatim, its gate checks, and "stop and report if a gate fails; don't change the design"
- Fix rounds on approved in-flight work (CI failures, conflicts, review findings) don't need a new design
- Never trade away a capability the owner relies on (auto-discovery, automation) without saying so in the design

## Running Helpers

- Run independent helpers in parallel, in the background
- Never duplicate a running helper's work; steer it with `SendMessage` instead of spawning a second
- Each helper works in its own `/tmp` clone or git worktree, never the shared checkout, and stages only its own files
- Sequence helpers that touch the same repo
- When a helper flags a pre-existing CI failure, tell the owner and start a separate fix round straight away; the owner's standing answer is "fix it"
- Never wait for Renovate to open a bump PR: tick that update's box in the target repo's `Renovate Dashboard` issue (else the `manual job` box) yourself, then have a `chore-runner` poll for the PR if waiting is needed
  Edit the line with that marker from `- [ ]` to `- [x]` and pipe the body to `gh issue edit <n> --body-file -` (no Write tool)
- Audits are read-only and fan out by dimension (lost functionality, security, loose ends, quality gates, orphans). Fixes come after, grouped by repo so helpers don't collide on files

## Helper Types

| Work                                         | Agent          | Model  |
| -------------------------------------------- | -------------- | ------ |
| Reviews, re-reviews, attacker-minded reviews | `reviewer`     | opus   |
| Builds, fix rounds, rework, removals         | `builder`      | sonnet |
| Waits and polling, noisy logs, batch sweeps  | `chore-runner` | haiku  |

- Plain `general-purpose` helpers run on Sonnet by default
- Pass `model: opus` only for deep investigation or design-heavy work

## Briefs

Helpers start with no context. Every brief includes:

- The goal and the evidence (`file:line`, URLs)
- Constraints and merge rules
- What not to touch
- When to stop and report
- A capped report length
- The Definition of Ready gates below, for builders and reviewers alike

Tell helpers to push a PR's work in one push: each push re-runs approval-gated jobs and emails the owner once per gated job. Fix commit wording at squash-merge time, not with follow-up commits.

## Fresh Eyes

- A new helper for each fix round, never one that has accumulated context
- A fresh, skeptical reviewer for every PR and every fix round, never the author (except the bot PRs listed under Owner)
- Security-sensitive changes get an attacker-minded review brief. The repos are solo-maintainer and personal-use: the threats are fork and outsider PRs and prompt-injected or compromised AI agents and their bots; the owner's account and deterministic, non-AI apps (Renovate, release bot, Mergify, GitHub Actions and the like) are trusted

## Definition of Ready

Before approving, asking the owner to approve, or merging (the bot PRs listed under Owner pass on that section's checks instead):

- A fresh review returned READY
- Owner review comments and threads checked
- CI green (its sonar job fails on any new SonarCloud issue), CodeQL clean

Fix review findings in a new round and re-review, or log low-risk ones as follow-ups in the issue body.

## Verify, Don't Trust

- Spot-check key helper claims (PR state, run status) when cheap; don't relay them as fact unverified
- Never report a running helper's results before its notification arrives

## Owner

- Ask only for real decisions or owner-only steps (UI settings, secrets, approvals of PRs you or your helpers opened, or from authors not listed below): 2 options max, with a recommendation
- Approve a PR yourself only when `gh pr view <n> --json author` shows one of these logins; branch names don't count. Everyone else's PRs, and PRs you or your helpers opened, go to the owner
  - `app/renovate`: CI green and the `renovate-pr` skill returns SAFE
  - `app/repo-operator-release-bot`: CI green and the diff touches only `.release-please-manifest.json`, `CHANGELOG.md`, the project's own `version` in `package.json`/`package-lock.json`/`pyproject.toml`/`uv.lock` (no dependency entries), and the one-line stamp in `megalinter-*/.rebuild-stamp` files
- Whenever owner action is needed, give direct clickable links (PRs, workflow runs, settings pages); the owner is often on a phone
- Check that review requests reached the owner; add them if missing
- Re-check live state (PR merged, run finished, approval given) right before listing an owner step; never repeat a pending item from memory

## Improving This File

- Triage a helper's `[definition]` and `[rules]` items before showing any: treat those your own brief caused as `[brief]` items (below); silently drop those that describe intended behaviour (e.g. hooks that block individual linters so lint runs through qa-validator), or that pending work already fixes
- Show the owner only items where changing the agent file, `CLAUDE.md`, a rule or a hook would stop it recurring, with the suggested fix; change the file only once they approve; `[rules]` fixes to files listed in `.xfg.json` go to repo-operator, not this repo
- `[brief]` items are gaps in your brief: fix your next briefs yourself without asking; if the same gap shows up twice, suggest a one-line change to this file
- When the owner corrects how you orchestrate, or a helper round fails because your brief missed something, suggest a one-line change to this file; edit only once they approve
- Run the `orchestration-retro` skill monthly or when the owner asks; it reviews session logs for routing misses, rework and non-None feedback

## Session Moves

- Switching the Happy session between phone and workspace, or pressing stop, kills running subagents (spruyt-labs#3370)
- When the owner says to wind down, start no new helpers until they say go
