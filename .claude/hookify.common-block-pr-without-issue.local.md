---
name: block-pr-without-issue
enabled: false
event: bash
pattern: gh\s+pr\s+create\s+(?!.*--title\s+["'][^"']*\(#\d+\))
action: block
---

**PR title must include issue reference.**

Format: `<type>(<scope>): description (#<issue#>)`
Example: `feat(auth): add login support (#42)`

The issue number enables workflow tracking and auto-close on merge.
