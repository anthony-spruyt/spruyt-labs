---
name: block-kubectl-secrets
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: command_match
    pattern: '^kubectl\b(?=.*\sget\s)(?=.*\s(?:[\w.-]+,)*secrets?(?:\.[\w.]+)?(?:,[\w.-]+)*(?:/\S*)?(?=\s|$))(?=.*[\s''](?:(?:-o\s*=?\s*|--output[=\s]\s*)''?(?:yaml|json|jsonpath|go-template|template|custom-columns)|--template[=\s]))'
    fallback: 'kubectl\b(?=.*\sget\s)(?=.*\ssecrets?\b)(?=.*\s(?:(?:-o\s*=?\s*|--output[=\s]\s*)(?:yaml|json|jsonpath|go-template|template|custom-columns)|--template[=\s]))'
---

🚫 **Blocked: kubectl get secret with output format**

**What was blocked:** `kubectl get secret` with `-o`/`--output` `yaml`, `json`, `jsonpath`, `go-template` or `custom-columns`, or with `--template`

**Why:** These commands output base64-encoded secrets to stdout, which could:

- Appear in terminal history
- Be logged by shell recording
- Be accidentally shared in screenshots

**If you need this:** Ask the user to run the command manually.

**False positive?** Open an issue: `gh issue create --repo anthony-spruyt/spruyt-labs --title "False positive: block-kubectl-secrets" --label bug` and describe the blocked command in the body using `--body-file` to avoid re-triggering hooks.
