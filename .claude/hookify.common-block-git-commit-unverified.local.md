---
name: common-block-git-commit-unverified
enabled: false
event: bash
pattern: (^|[;&|]\s*)git\s+commit\s+-
action: block
---

**BLOCKED: Use the git-workflow agent for commits.**

Direct `git commit` is blocked. Use the Task tool with `subagent_type="git-workflow"` instead.
