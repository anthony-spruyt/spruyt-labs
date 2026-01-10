---
name: common-warn-pr-create
enabled: false
event: bash
pattern: gh\s+pr\s+create.*--title\s+["'][^"']*\(#\d+\)
action: warn
---

**PR created.** Return results. Next agents: **pr-review** (if available) → **merge-workflow**.
