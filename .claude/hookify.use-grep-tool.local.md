---
name: use-grep-tool
enabled: true
event: bash
pattern: \brg\s
action: block
---

**BLOCKED: Use the Grep tool instead of rg**

You attempted to search with `rg` (ripgrep). Use Claude's Grep tool instead.

**Why?**
- Grep tool is built into Claude
- Optimized for codebase searches
- Supports output modes: content, files_with_matches, count

**What to do:**
Use the Grep tool with pattern and optional path/glob filters.
