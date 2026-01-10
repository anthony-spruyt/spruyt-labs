---
name: block-branch-without-issue
enabled: false
event: bash
pattern: git\s+(checkout\s+-b|branch\s+(?!-|--show|--list|--all|-[arlvd]))\s*(?!\S+-\d+(\s|$))\S+
action: block
---

**Branch name must include issue number.**

Format: `<type>/<description>-<issue#>`
Examples: `feat/add-auth-42`, `fix/login-bug-15`

Use **issue-workflow** first to get an issue number.
