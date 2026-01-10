---
name: common-warn-pr-merge
enabled: false
event: bash
pattern: gh\s+pr\s+merge
action: warn
---

**Merged.** Verify branch deleted and issue closed, then return results.
