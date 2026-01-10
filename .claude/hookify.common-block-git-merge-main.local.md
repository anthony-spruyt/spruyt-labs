---
name: common-block-git-merge-main
enabled: false
event: bash
pattern: git\s+merge\s+.*(main|master)
action: block
---

**BLOCKED: Don't merge main/master directly**

Use pull requests instead. Create a feature branch, push it, and use `gh pr create` followed by `gh pr merge` after approval.
