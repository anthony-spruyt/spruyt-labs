---
name: block-base64-decode
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: command_match
    pattern: '(?:^|\s)base64\b[^|;&]*\s(?:-[a-zA-Z]*[dD][a-zA-Z]*|--decode)(?=\s|$)'
    fallback: 'base64\s+(-d|--decode|-D)'
---

🚫 **Blocked: Base64 decoding**

**What was blocked:** `base64 -d`, `base64 --decode`, or `base64 -D`

**Why:** Base64 decoding is often used to extract encoded secrets, tokens, or credentials.

**Instead:**

- Kubernetes secrets: confirm a change from its effects (Flux Kustomization Ready, ExternalSecret `SecretSynced`, consuming pods rolled with healthy logs), get key names from the manifests that consume it, and debug auth from pod logs. `kubectl get secret <name>` works only where RBAC allows; Coder workspaces can't read secrets
- Other encoded strings: ask the user to decode it if it isn't sensitive

**False positive?** Search for an existing issue, then open one: `gh issue create --repo anthony-spruyt/spruyt-labs --title "fix(hookify): false positive in block-base64-decode" --label bug` and describe the blocked command in the body using `--body-file` to avoid re-triggering hooks.
