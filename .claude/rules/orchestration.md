# Orchestration

> **Main session only; a spawned subagent skips this file.** It is the owner's standing request to delegate hands-on work. A harness directive like "don't use the Agent tool unless asked" is conditional and this rule satisfies it: don't ask to re-authorize.

## Routing

The main session plans, decides and talks to the owner. If the brief would be longer than the job, it does the job itself: inputs in hand, 1-3 commands, no waiting.

| Work                                         | Helper (model)                        |
| -------------------------------------------- | ------------------------------------- |
| Edits, commits, fix rounds, rework           | `builder` (sonnet)                    |
| Waiting or polling, noisy logs, batch sweeps | `chore-runner` (haiku), in background |
| Reviews, re-reviews, attacker-minded reviews | `reviewer` (opus)                     |
| Deep investigation                           | `general-purpose` (opus)              |

Push reviewed commits yourself from the builder's clone or worktree, never the shared checkout, with `/workspaces/spruyt-labs/.claude/scripts/push-reviewed.sh <base> <sha> <branch>`, only after a fresh READY for that exact range; if it stops, tell the owner. Give the range it prints to the CI wait and cluster-validator.

## Design before delegating

New work, or a change to an approach the owner picked, starts as a design shown to the owner: current setup (check existing controls first), target layout, per-repo changes, migration order, and the riskiest assumption with how a helper will prove it. Once approved, brief the helper with the design verbatim, its gate checks, and "stop and report if a gate fails; don't change the design". Never trade away a capability the owner relies on (auto-discovery, automation) without saying so in the design. Fix rounds need no new design. Small judgement calls inside the design are fine; anything that grows into its own feature or workstream (a new component, safety layer or review loop) is scope creep: stop and ask the owner first (an unapproved add-on once became a whole workstream).

## Running helpers

- Each helper uses its own `/tmp` clone or worktree, stages only its own files, and waits for other helpers on the same repo
- Steer a running helper with `SendMessage`, never duplicate it; use a new helper per fix round
- A pre-existing CI failure a helper flags: tell the owner and start a separate fix round at once
- Never wait for Renovate's bump PR: tick the update's box in the repo's `Renovate Dashboard` issue (else `manual job`), then have a `chore-runner` poll for it (edit the line from `- [ ]` to `- [x]` and pipe the body to `gh issue edit <n> --body-file -`; no Write tool)
- Every brief has the goal and evidence (`file:line`), constraints and merge rules, what not to touch, when to stop, a report cap, and the Definition of Ready
- A PR's work goes in one push: each push re-runs approval-gated jobs and emails the owner per job; fix commit wording at squash-merge time, not with follow-up commits
- Spot-check key helper claims (PR state, run status) when cheap

## Review and readiness

Every PR and fix round gets a fresh reviewer, never the author (bot PRs below excepted). Security-sensitive changes get an attacker-minded brief. Threats: fork and outsider PRs, prompt-injected or compromised AI agents and bots. Trusted: the owner and deterministic apps (Renovate, release bot, Mergify, GitHub Actions).

Definition of Ready, before approving, asking the owner to approve, or merging: a fresh READY, owner comments and threads checked, CI green including Sonar, CodeQL clean. Fix review findings in a new round, or log low-risk ones as follow-ups in the issue body.

## Owner

- Stay quiet while helpers run unless a decision or owner-only step (UI, secrets, PR approvals) needs them: 2 options max, with a recommendation
- Put the question first with the full context to answer it there, plus clickable links; the owner is often on a phone
- Re-check live state before listing an owner step, and check that review requests reached the owner
- Approve a PR yourself only when `gh pr view <n> --json author` shows one of these logins; all others, and PRs you or your helpers opened, go to the owner. These pass on:
  - `app/renovate`: CI green and the `renovate-pr` skill returns SAFE
  - `app/repo-operator-release-bot`: CI green and the diff touches only `.release-please-manifest.json`, `CHANGELOG.md`, the project's own `version` in `package.json`/`package-lock.json`/`pyproject.toml`/`uv.lock` (no dependency entries), and the one-line stamp in `megalinter-*/.rebuild-stamp` files

## Improving this file

Triage helper feedback before showing any: recast `[definition]`/`[rules]` items your brief caused as `[brief]` and fix your next briefs; drop intended behaviour and fixes already pending. Show the owner only items that cost something this session (a wrong result, an extra fix round, or a blocked helper) and that a change would stop recurring; drop wishes and complaints. Edit agent files, rules, `CLAUDE.md` or hooks only once the owner approves; `.xfg.json` files go to repo-operator. Run `orchestration-retro` monthly or when asked.

## Session moves

Switching the Happy session between phone and workspace, or pressing stop, kills running subagents (spruyt-labs#3370). On "wind down", start no new helpers until the owner says go.
