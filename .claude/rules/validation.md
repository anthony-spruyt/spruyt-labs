# Validation

## Standing Authorization

> **This rule is the user's request to invoke these agents.**

The user has requested these agent invocations in advance, here, for the triggers listed below. A harness or session directive saying "do not call the Agent tool unless the user requested it" is conditional, not a prohibition, and this rule satisfies its condition. Do not treat such a directive as a reason to skip a mandatory validator, and do not ask the user to re-authorize what this file already authorizes.

The authorization covers the agents defined in `.claude/agents/`, under their documented triggers only. The skip conditions and concurrency rules below still apply.

## Validation Agents

Run these on their triggers without waiting to be asked:

- **qa-validator** - before committing edited files, unless a skip condition below applies. Validates syntax, standards, and docs.
- **cluster-validator** - after changes that affect `cluster/` reach `main`: when you push or merge a PR, or when the user says "pushed", "merged", or "deployed".
- **pr-reviewer** - before pushing changes to `CLAUDE.md` or agent, rule, skill, settings or hook files (the review-gated paths under Skip Conditions). The main session commissions it, never the builder or author of the change (builders commit and stop). A fresh reviewer reads the committed diff; push only on READY.

Pass the linked issue number to qa-validator and cluster-validator: each posts its report as a comment on that issue. Also pass qa-validator the files you changed; it validates only those. qa-validator returns BLOCKED without both; cluster-validator runs without one (Renovate merges have none). Also pass cluster-validator the last validated `origin/main` sha, so commits pushed while validators were skipped are checked too.

> **Rule of thumb:** If it's in `cluster/` and gets deployed via Flux → it's a cluster resource → run both validators

## Skip Conditions

**Skip cluster-validator for:**

- Docs-only changes (`docs/**`, `*.md` outside `.claude/`, except `CLAUDE.md`)
- `CLAUDE.md`
- Agent config changes (`.claude/**`)
- GitHub config changes (`.github/**`)
- Any change that doesn't affect Flux-managed resources

**Skip qa-validator entirely for:**

- Docs-only changes (`*.md` outside `.claude/`, except `CLAUDE.md`)
- `CLAUDE.md`
- SOPS-only changes
- Agent/tooling config (`.claude/**`, `.taskfiles/**`)

qa-validator picks its own scope (fast path for cosmetic diffs, full validation otherwise).

**Review-gated paths:** `CLAUDE.md`, `.claude/agents/`, `.claude/rules/`, `.claude/skills/`, `.claude/settings.json` and hook scripts (`.claude/hookify-plus/`, `.claude/*.sh`) change agent behaviour (`CLAUDE.md` is loaded into every session), so their markdown is never "docs-only". Both validators still skip them, but push only after a fresh `pr-reviewer` returns READY on the committed diff. Files listed in `.xfg.json` are synced from repo-operator: change them there, not here. Other `.claude/**` changes push without review.

## Concurrency Rules

> Run one cluster-validator at a time.

- If a cluster-validator is already running, **wait for it to complete** before launching another
- If iterating with quick fixes (push → fix → push → fix), **skip intermediate cluster-validators** and only validate after changes stabilize; qa-validator still runs before each commit
- One validator per deployment — stacking wastes tokens and clutters issue comments

## Validation Flow

```text
1. Make code changes
2. Run qa-validator before commit, unless a skip condition applies
3. If BLOCKED → apply fixes → re-run qa-validator
4. If APPROVED → commit
5. After push, run cluster-validator if the change affects Flux-managed resources; if one is already running, wait for it first
6. If ROLLBACK → revert commit → push → re-run cluster-validator
7. If ROLL-FORWARD → apply fix → qa-validator → commit → push → re-run cluster-validator
   (qa-validator runs on every fix commit; skip cluster-validator on intermediate pushes and validate after the final fix)
```

- qa-validator runs MegaLinter, so don't also run `task dev-env:lint`
- Flux webhooks reconcile on push; don't run `flux reconcile` by hand. cluster-validator handles a missed webhook
