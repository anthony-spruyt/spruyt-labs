---
name: block-issue-close
enabled: false
event: bash
pattern: gh issue close
action: block
---

**WARNING: Issue closing requires user confirmation**

You attempted to close a GitHub issue. Remember:

1. **Only the user decides when issues are closed** - not agents or validators
2. **Validation rules explicitly state**: "validators must NEVER close issues"
3. **Workflow rules state**: "Close after user confirms"

The user will close issues manually when they are satisfied the work is complete.

**What to do instead:**

- Comment on the issue with your findings
- Report validation status
- Let the user decide when to close
