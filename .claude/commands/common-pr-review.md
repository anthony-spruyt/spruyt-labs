---
description: Review a pull request against project standards and security requirements
allowed-tools: Read, Glob, Grep, Bash(git:*), Bash(gh:*)
---

# PR Review

Review pull request $ARGUMENTS using project standards and security requirements.

## Workflow

### 1. Fetch PR Details

```bash
gh pr view $ARGUMENTS --json title,body,files,additions,deletions,baseRefName,headRefName
gh pr diff $ARGUMENTS
```

### 2. Load Review Context

- Check `.claude/agents/` for project-specific review agents
- Check `.claude/rules/` for project conventions
- Check `CLAUDE.md` for project standards

### 3. Review Changes

Evaluate all changes against:

**Security (Critical)**

- No secrets, credentials, or API keys in code
- No hardcoded sensitive values
- Safe command execution (no injection vulnerabilities)
- Proper input validation at boundaries

**Code Quality**

- Follows existing codebase patterns
- No unnecessary code duplication
- Clear naming and structure
- Appropriate error handling

**Documentation**

- Changes documented if user-facing
- Comments where logic isn't self-evident

**Testing**

- Test coverage for new functionality
- Existing tests still pass

### 4. Provide Feedback

Use [Conventional Comments](https://conventionalcomments.org/) format:

```
<label> [decorations]: <subject>

[discussion]
```

**Labels:**

- `issue` - Must fix (blocking)
- `suggestion` - Should consider (non-blocking)
- `question` - Needs clarification
- `nitpick` - Minor preference
- `praise` - Positive highlight
- `chore` - Task before merge
- `todo` - Small necessary change

**Decorations:** `(blocking)`, `(non-blocking)`, `(security)`, `(if-minor)`

### 5. Post Review

```bash
gh pr review $ARGUMENTS --comment --body "<review>"
```

Or with approval/changes requested:

```bash
gh pr review $ARGUMENTS --approve --body "<review>"
gh pr review $ARGUMENTS --request-changes --body "<review>"
```

## Output Format

```markdown
## PR Review: #<number> - <title>

### Summary

[Brief assessment of the PR]

### Findings

issue (security): [subject]
[discussion]

---

suggestion (non-blocking): [subject]
[discussion]

---

praise: [subject]
[discussion]

### Verdict

[ ] APPROVED - Ready to merge
[ ] CHANGES REQUESTED - See issues above
[ ] COMMENT - Questions need answers
```
