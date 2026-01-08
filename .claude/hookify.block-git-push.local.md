---
name: block-git-push
enabled: true
event: bash
pattern: git push
action: block
---

**BLOCKED: git push is not allowed**

This repository requires manual pushes (see CLAUDE.md Hard Rules).

**Why?**
- User must verify changes before pushing to remote
- Prevents accidental pushes to protected branches

**What to do instead:**
1. Inform the user that changes are ready to push
2. Let the user run `git push` manually
3. After push, run cluster-validator if changes affect `cluster/`
