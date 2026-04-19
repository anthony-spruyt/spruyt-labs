# Workflow

## GitHub Issues

### Lifecycle

1. Search for existing issue by keywords
2. Create issue if needed using template fields
3. Track issue number throughout work
4. Reference in commits: `Ref #123`
5. Validators post results as issue comments
6. Close after user confirms

### Issue Types

Read templates from `.github/ISSUE_TEMPLATE/` to get title prefix, labels, and required fields.

| Type | Template | Label | Title Prefix |
|------|----------|-------|--------------|
| Feature | `feature_request.yml` | `enhancement` | `feat(scope):` |
| Bug | `bug_report.yml` | `bug` | `fix(scope):` |
| Chore | `chore.yml` | `chore` | `chore(scope):` |
| Docs | `docs.yml` | `documentation` | `docs(scope):` |
| Infra | `infra.yml` | `infra` | `infra(scope):` |

### Required Fields

| Type | Required Fields |
|------|-----------------|
| Feature | Summary, Motivation, Acceptance Criteria, Affected Area |
| Bug | Description, Expected Behavior, Actual Behavior, Steps to Reproduce, Affected Area |
| Chore | Summary, Motivation, Chore Type, Affected Area |
| Docs | Summary, Motivation, Documentation Type, Affected Area |
| Infra | Summary, Motivation, Infrastructure Type, Affected Area, Planned Changes, Rollback Plan, Risk Level |

### Affected Area Options

- Apps (cluster/apps/)
- Flux/GitOps (cluster/flux/)
- Infrastructure (Talos, networking, storage)
- Monitoring/Observability
- Security (network policies, auth)
- Tooling (.taskfiles/, scripts)
- Documentation
- CI/CD (.github/)
- Other

### Additional Labels

- `blocked` - Waiting on upstream fix or external dependency
- `dep/major`, `dep/minor`, `dep/patch` - Dependency version changes (Renovate)

## Commits

Skip qa-validator for trivial changes (typos, single-line fixes, SOPS-only). Pre-commit hooks catch basic issues.

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

| Layer | When | Speed | Purpose |
|-------|------|-------|---------|
| **qa-validator** | Before commit | Minutes | Comprehensive MegaLinter + schema/docs verification (shift-left) |
| **Pre-commit** | At commit | Seconds | Fast syntax guards (yamllint, gitleaks, prettier) |
| **CI** | Push/PR | Minutes | Safety net, PR gate |

> **Note:** qa-validator runs MegaLinter. No need to run `task dev-env:lint` separately if qa-validator passed.
