---
name: block-kubectl-exec-secrets
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: command_match
    pattern: '^kubectl\b.*\sexec\s.*\s--\s(?:.*[\s''"])?(?:(?:cat|head|tail|less|more|strings|xxd|od|base64)\s.*(?:secret|token|password|credential|\.pem|\.key\b)|env(?=\s*(?:$|[|;&>)''"]))|printenv\b)'
    fallback: 'kubectl\b.*\sexec\s.*\s--\s(?:.*[\s''"])?(?:(?:cat|head|tail|less|more|strings|xxd|od|base64)\s.*(?:secret|token|password|credential|\.pem|\.key\b)|env(?=\s*(?:$|[|;&>)''"]))|printenv\b)'
---

🚫 **Blocked: kubectl exec reading secrets**

**What was blocked:** `kubectl exec` attempting to read secrets, credentials, or environment variables

**Dangerous patterns:**

- `kubectl exec ... cat /var/run/secrets/*` - Kubernetes service account tokens
- `kubectl exec ... cat *secret*` - Secret files
- `kubectl exec ... cat *token*` - Token files
- `kubectl exec ... cat *password*` - Password files
- `kubectl exec ... cat *.pem` - Private keys
- `kubectl exec ... env` - Environment variables (may contain secrets)
- `kubectl exec ... printenv` - Environment variables

**If you need this:** Ask the user to run the command manually or describe what information you need.

**Safe alternatives:**

- Check pod logs: `kubectl logs <pod>`
- Describe pod: `kubectl describe pod <pod>`
- Check configmaps: `kubectl get configmap <name> -o yaml`

**False positive?** Search for an existing issue, then open one: `gh issue create --repo anthony-spruyt/spruyt-labs --title "fix(hookify): false positive in block-kubectl-exec-secrets" --label bug` and describe the blocked command in the body using `--body-file` to avoid re-triggering hooks.
