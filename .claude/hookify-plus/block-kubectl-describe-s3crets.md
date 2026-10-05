---
name: block-kubectl-describe-secrets
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: command_match
    pattern: '^kubectl\b.*\sdescribe\s(?:.*\s)?(?:[\w.-]+,)*secrets?(?:\.[\w.]+)?(?:,[\w.-]+)*(?:/\S*)?(?=\s|$)'
    fallback: 'kubectl\s+(?:.*\s)?describe\s+(?:.*\s)?secrets?\b'
---

🚫 **Blocked: kubectl describe secret**

**What was blocked:** `kubectl describe secret`

**Why:** It lists every key name and size. Get key names from the manifests that consume the secret (`secretKeyRef`, `envFrom`) instead.

**Safe alternatives:**

- List secret names: `kubectl get secrets`
- Check one secret exists and its key count: `kubectl get secret <name>`

**False positive?** Search for an existing issue, then open one: `gh issue create --repo anthony-spruyt/spruyt-labs --title "fix(hookify): false positive in block-kubectl-describe-secrets" --label bug` and describe the blocked command in the body using `--body-file` to avoid re-triggering hooks.
