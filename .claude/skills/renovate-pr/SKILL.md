---
name: renovate-pr
description: >
  Triage one Renovate PR, then merge it or label it `blocked`. Use when the user passes a PR number such as #3337 and asks to
  triage, check, or merge a Renovate/dependency PR.
argument-hint: <pr-number>
arguments: [pr]
---

# Renovate PR Triage

Target PR: `$pr`. Strip any leading `#` to get the number `<N>`.

## 1. Confirm it is a Renovate PR

```bash
gh pr view <N> --json number,title,author,state,labels,headRefName,files
```

Stop and tell the user if the PR is not open, or is not from Renovate (author `app/renovate` or branch `renovate/*`).

If the PR touches `talos/topf.yaml`, stop and hand off: a `kubernetesVersion` bump goes to the `kubernetes-upgrade` skill, a `talosVersion` bump to the `talos-upgrade` skill. Flux doesn't apply that file, so merging it alone records a version the nodes aren't running.

Then run `gh pr checks <N>`. If a check named `Agent triage` is not finished (pending, queued or in progress), stop: tell the user the agent platform is already triaging this PR, give the check's link, and do nothing else (no analyzer, no labels, no comment). A finished `Agent triage` check doesn't block; continue.

Then read the comments: `gh pr view <N> --comments`.

## 2. Get a verdict

If a comment holds an `agent-platform:renovate-triage` verdict and the diff still bumps the same versions (a rebase changes the head sha, not the bump), skip the analyzer: that changelog read stands. Check each risk named there or in an owner comment yourself (live cluster, upstream issue state), decide the verdict, and go to step 3.

Otherwise spawn the `renovate-pr-analyzer` subagent. Get the repo with `gh repo view --json nameWithOwner -q .nameWithOwner`. Prompt:

```text
Analyze this Renovate dependency update PR for breaking changes and risks.
Repository: <owner/repo>
PR #<N>: <title>

Local run: also add a `**New features:**` section after the verdict template. From the
changelog range you already read, list new upstream features, options, or fixes that would
benefit this cluster, given the config files you read. For each: one line on what it is, why
it helps us, and the config file it would touch. Skip features we can't use. Write `None`
if nothing qualifies.
```

The feature ask lives here, not in the agent file, because the agent platform's triage prompt reads the verdict template and must not see extra fields.

## 3. Act on the verdict

Labels left by an earlier verdict stay until the skill merges the PR or adds a new label. SAFE (before the merge), BLOCKED and NEEDS_REVIEW (before adding theirs) first remove each of `blocked` and `agent/needs-human-review` that the PR carries (from step 1): `gh pr edit <N> --remove-label <label>`. FIXABLE leaves them as they are.

**SAFE**

1. Check CI: `gh pr checks <N>`. Ignore `renovate/stability-days`, `Mergify` (they never clear on early-triggered PRs) and `Agent triage` (not CI); none blocks a direct merge. If other checks are pending, re-check every minute until they finish (don't use `--watch`, it waits on the ignored checks too). If any other check fails, treat as not SAFE and follow the **NEEDS_REVIEW** steps (label and comment).
2. Remove stale labels (above), then merge: `gh pr merge <N> --squash`. If branch rules block it, approve with `gh pr review <N> --approve` and merge again.
3. If the PR touched `cluster/`, run `cluster-validator` (no issue number needed). If one is already running, wait for it to finish, then run.

**FIXABLE**

1. Comment on the PR with the verdict, summary, fix, and reasons: `gh pr comment <N> --body-file -`
2. Do not merge or label. Offer to fix it: issue from `.github/ISSUE_TEMPLATE/chore.yml`, fix on the PR branch, qa-validator, push, then re-run this skill.

**BLOCKED**

1. Add the label: `gh pr edit <N> --add-label blocked`
2. Comment on the PR with the verdict, summary, and reasons: `gh pr comment <N> --body-file -`
3. Do not merge.

**NEEDS_REVIEW**

1. Add the label: `gh pr edit <N> --add-label agent/needs-human-review`
2. Comment on the PR with the verdict, summary, and reasons: `gh pr comment <N> --body-file -`
3. Do not merge.

## 4. Report to the user

Keep it short:

- Verdict and one-line reason
- What you did: merged, commented, or labelled `blocked` or `agent/needs-human-review`
- cluster-validator result, if run
- New features worth adopting, from the analyzer if it ran. If any, offer to open an `enhancement` issue per feature using `.github/ISSUE_TEMPLATE/feature_request.yml`. Do not open them without asking.

## Rules

- Never merge on anything but SAFE with green CI.
- Never close the PR, even on BLOCKED. Leave that to the user.
- Never put IPs, CIDRs, or secrets in PR comments.
- Report CI as one state: green, failing <check> or pending. Never mention ignored checks, Mergify, approvals, or merge rules.
