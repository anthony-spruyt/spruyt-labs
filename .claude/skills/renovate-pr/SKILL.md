---
name: renovate-pr
description: >
  Triage one Renovate PR end to end. Runs the renovate-pr-analyzer subagent, merges the PR
  when the verdict is SAFE or labels it `blocked` otherwise, and reports new upstream
  features worth adopting. Use when the user passes a PR number such as #3337 and asks to
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

## 2. Run the analyzer

Spawn the `renovate-pr-analyzer` subagent. Get the repo with `gh repo view --json nameWithOwner -q .nameWithOwner`. Prompt:

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

The feature ask lives here, not in the agent file, because the n8n orchestrator parses the agent's verdict template and must not see extra fields.

## 3. Act on the verdict

**SAFE**

1. Check CI: `gh pr checks <N>`. If checks are pending, wait with `gh pr checks <N> --watch`. If any fail, treat as not SAFE.
2. If the PR has the `blocked` label, remove it: `gh pr edit <N> --remove-label blocked`
3. Merge: `gh pr merge <N> --squash`. Ignore Mergify's approval check.
4. If the PR touched `cluster/`, run `cluster-validator` (no issue number needed). Skip it if one is already running.

**FIXABLE, RISKY, or BREAKING**

1. Add the label: `gh pr edit <N> --add-label blocked`
2. Comment on the PR with the analyzer's verdict, summary, and breaking changes:
   `gh pr comment <N> --body-file -`
3. Do not merge. For FIXABLE, offer to apply the fix the summary describes.

## 4. Report to the user

Keep it short:

- Verdict and one-line reason
- What you did: merged, or labelled `blocked`
- cluster-validator result, if run
- New features worth adopting, from the analyzer. If any, offer to open an `enhancement` issue per feature using `.github/ISSUE_TEMPLATE/feature_request.yml`. Do not open them without asking.

## Rules

- Never merge on anything but SAFE with green CI.
- Never close the PR, even on BREAKING. Leave that to the user.
- Never put IPs, CIDRs, or secrets in PR comments.
