---
name: common-block-git-push
enabled: false
event: bash
pattern: (^|[;&|]\s*)git\s+push(\s|$)
action: block
---

**BLOCKED: Use the git-workflow agent to push.**

Direct `git push` is blocked. Use the Task tool with `subagent_type="git-workflow"` instead.
