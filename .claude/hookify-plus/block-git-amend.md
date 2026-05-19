---
name: block-git-amend
enabled: true
event: bash
pattern: --amend
action: block
---

**BLOCKED: git commit --amend is not allowed**

This repository follows a "no amend" policy (see CLAUDE.md Hard Rules).

**Why?**

- Multiple agents may work in the same environment simultaneously
- Amending commits can cause conflicts and lost work
- Clean commit history is easier to review and revert

**What to do instead:**

1. Create a new commit with the fix/addition
2. If you made an error in the previous commit message, create a new commit that references it
3. Let the user squash commits during PR merge if desired

**Example:**

```bash
# Instead of amending, create a new commit
git add <files>
git commit -m "fix(scope): correct the previous change"
```
