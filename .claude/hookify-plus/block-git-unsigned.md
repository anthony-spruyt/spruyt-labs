---
name: block-git-unsigned
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: regex_match
    pattern: '\bgit\b[^;&|\n]*(?:\s--no-(?:gpg-)?sign(?![\w-])|--config-env[=\s]\s*["\x27]?(?:commit|tag)\.gpgsign|\s-c\s*["\x27]?(?:gpg\.[^\s"\x27]*|user\.signingkey|(?:commit|tag)\.gpgsign=(?:false|0|no|off)?(?![\w.-]))|\sconfig\b[^;&|\n]*(?:\bunset(?:-all)?\b[^;&|\n]*\b(?:commit|tag)\.gpgsign|\b(?:commit|tag)\.gpgsign["\x27]?\s+["\x27]?(?:false|0|no|off)(?![\w.-])))|\bGIT_CONFIG_KEY_\d+=\S*gpgsign|\bGIT_CONFIG_PARAMETERS=.*gpgsign'
---

**BLOCKED: turning off git commit signing is not allowed**

Every environment signs commits with SSH, and every repo's rulesets reject unsigned commits. An unsigned commit on a PR cannot be merged.

**Why?**

- GitHub's "Commits must have verified signatures" rule blocks the merge
- Fixing it afterwards means rewriting history and a force-push

**What to do instead:**

1. Keep signing on: no `--no-gpg-sign`, no `-c commit.gpgsign=false`, no `git config` changes to signing, no `GIT_CONFIG_*` overrides
2. If signing fails, stop and report the exact error to the main session; do not work around it
3. If unsigned commits are already pushed, re-create them as new signed commits (no amend) and report that a force-push is needed
