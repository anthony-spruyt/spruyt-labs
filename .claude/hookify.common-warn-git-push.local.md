---
name: common-warn-git-push
enabled: false
event: bash
pattern: command\s+git\s+push
action: warn
---

**Pushed.** Continue with PR creation if needed, otherwise Next agents: **pr-review** (if available) → **merge-workflow**.
