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

- Confirm a secret change from its effects: the Flux Kustomization is Ready at the commit (SOPS), `kubectl get externalsecret <name>` shows `SecretSynced` (ESO), and the consuming pods rolled (Reloader, or a manual restart) with logs showing the new setting works
- `kubectl get secrets` and `kubectl get secret <name>` list names and key counts only where RBAC allows; Coder workspaces can't read secrets

**False positive?** Search for an existing issue, then open one: `gh issue create --repo anthony-spruyt/spruyt-labs --title "fix(hookify): false positive in block-kubectl-describe-secrets" --label bug` and describe the blocked command in the body using `--body-file` to avoid re-triggering hooks.
