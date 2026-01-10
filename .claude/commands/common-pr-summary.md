---
description: Generate a pull request summary for the current branch changes
allowed-tools: Bash(git:*), Bash(gh:*)
---

# PR Summary Generator

Generate a pull request summary for the current branch.

## Workflow

### 1. Analyze Current Branch

```bash
# Get branch info
git branch --show-current
git log main..HEAD --oneline

# Get change statistics
git diff main...HEAD --stat
git diff main...HEAD --numstat
```

### 2. Categorize Changes

Group modified files by type:

- **Features** - New functionality
- **Fixes** - Bug fixes
- **Refactoring** - Code restructuring
- **Documentation** - Docs/comments
- **Tests** - Test additions/changes
- **Configuration** - Config file changes

### 3. Identify Breaking Changes

Check for:

- API changes (function signatures, endpoints)
- Configuration schema changes
- Removed features or deprecated code
- Database migrations

### 4. Generate Summary

Create PR description following this format:

```markdown
## Summary

- [Bullet points describing what changed and why]

## Changes

### [Category]

- `path/to/file.ext` - [brief description]

## Breaking Changes

[List any breaking changes, or "None"]

## Test Plan

- [ ] [How to verify the changes work]
- [ ] [Additional testing steps]
```

### 5. Output Options

**Copy to clipboard (if available):**

```bash
# macOS
echo "<summary>" | pbcopy

# Linux with xclip
echo "<summary>" | xclip -selection clipboard
```

**Create PR directly:**

```bash
gh pr create --title "<title>" --body "<summary>"
```

## Tips

- Keep summary concise (1-3 sentences)
- Focus on "why" not just "what"
- Group related changes together
- Include context for reviewers
- Reference related issues with `Fixes #123` or `Ref #123`
