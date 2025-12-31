---
name: use-read-tool
enabled: true
event: bash
pattern: ^cat\s+\S+\s*$
action: block
---

**BLOCKED: Use the Read tool instead of cat**

You attempted to read a file with `cat`. Use Claude's Read tool instead.

**Why?**
- Read tool is optimized for Claude's context
- Supports offset/limit for large files
- Better file handling and error messages

**What to do:**
Use the Read tool with the file path.
