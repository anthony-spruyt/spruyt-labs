---
name: use-edit-tool
enabled: true
event: bash
pattern: (sed|awk)\s+-i
action: block
---

**BLOCKED: Use the Edit tool instead of sed -i / awk -i**

You attempted in-place file editing with sed or awk. Use Claude's Edit tool instead.

**Why?**
- Edit tool tracks changes properly
- Better error handling and validation
- Integrates with Claude's file tracking

**What to do:**
Use the Edit tool with old_string and new_string parameters.
