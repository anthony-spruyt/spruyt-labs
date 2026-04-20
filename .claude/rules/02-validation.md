# Validation

## Validation Agents (MANDATORY)

> **Use these agents automatically - do NOT wait for user to request them.**

| Agent | When to Use | Trigger |
|-------|-------------|---------|
| **qa-validator** | Before ANY git commit that modifies files | After editing files (validates syntax, standards, docs) |
| **cluster-validator** | After changes are pushed/merged to main that affect cluster | When user says "pushed", "merged", or "deployed" OR when Claude merges a PR AND changes affect `cluster/` |

> **Rule of thumb:** If it's in `cluster/` and gets deployed via Flux → it's a cluster resource → run both validators

## Skip Conditions

**Skip cluster-validator for:**
- Docs-only changes (`*.md`, `docs/**`)
- Agent config changes (`.claude/**`)
- GitHub config changes (`.github/**`)
- Any change that doesn't affect Flux-managed resources

**Skip qa-validator for:**
- Docs-only changes (*.md files)
- SOPS-only changes

## Concurrency Rules

> **NEVER run a second validator while one is already running.**

- If a cluster-validator is already running, **wait for it to complete** before launching another
- If iterating with quick fixes (push → fix → push → fix), **skip intermediate validators** and only validate after changes stabilize
- One validator per deployment — stacking wastes tokens and clutters issue comments

## Validation Flow

```text
1. Make code changes
2. ALWAYS run qa-validator (before commit)
3. If BLOCKED → apply fixes → re-run qa-validator
4. If APPROVED → commit
5. User pushes
6. ALWAYS run cluster-validator (after push) — ONLY if none already running
7. If ROLLBACK → revert commit → user pushes → re-run cluster-validator
8. If ROLL-FORWARD → apply fix → commit → user pushes → re-run cluster-validator
   (skip validator on intermediate pushes, validate after final fix)
```
