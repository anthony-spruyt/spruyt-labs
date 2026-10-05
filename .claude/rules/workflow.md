# Workflow

## GitHub Issues

### Lifecycle

For changes that need an issue (see `constraints.md`):

1. Search for existing issue by keywords
2. Create issue if needed using template fields
3. Track issue number throughout work
4. Reference in commits: `Ref #123`
5. Validators post results as issue comments
6. Close issue after validated success; if validation isn't possible, get user confirmation first

### Issue Types

Read templates from `.github/ISSUE_TEMPLATE/` to get title prefix, labels, and required fields.

| Type    | Template              | Label           | Title Prefix    |
| ------- | --------------------- | --------------- | --------------- |
| Feature | `feature_request.yml` | `enhancement`   | `feat(scope):`  |
| Bug     | `bug_report.yml`      | `bug`           | `fix(scope):`   |
| Chore   | `chore.yml`           | `chore`         | `chore(scope):` |
| Docs    | `docs.yml`            | `documentation` | `docs(scope):`  |
| Infra   | `infra.yml`           | `infra`         | `infra(scope):` |

### Additional Labels

- `blocked` - Waiting on upstream fix or external dependency
- `dep/major`, `dep/minor`, `dep/patch` - Dependency version changes (Renovate)

## Commits

**After push:** Flux webhooks auto-reconcile - no manual `flux reconcile` needed.

## Pull Requests

Template: `.github/pull_request_template.md`

PR body structure:

```markdown
## Summary
<Brief description>

## Linked Issue
Closes #<number>

## Changes
- <change 1>
- <change 2>

## Testing
<How was this tested?>
```

## Linting Layers

| Layer            | When          | Speed   | Purpose                                                          |
| ---------------- | ------------- | ------- | ---------------------------------------------------------------- |
| **qa-validator** | Before commit | Minutes | Comprehensive MegaLinter + schema/docs verification (shift-left) |
| **Pre-commit**   | At commit     | Seconds | Fast guards (yamllint, gitleaks, markdownlint, shellcheck)       |
| **CI**           | Push/PR       | Minutes | Safety net, PR gate                                              |

> **Note:** qa-validator runs MegaLinter. No need to run `task dev-env:lint` separately if qa-validator passed.
