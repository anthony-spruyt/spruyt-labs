---
name: common-block-git-directory-flag
enabled: false
event: bash
pattern: git\s+(-C|--git-dir|--work-tree)[\s=]
action: block
---

**BLOCKED: Don't use `git -C` or directory flags**

These flags break bash whitelist patterns like `Bash(git:*)`. Run git commands from the working directory instead.
