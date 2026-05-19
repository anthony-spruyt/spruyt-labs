# Constraints

## Work Requirements

All work requires a linked GitHub issue. No exceptions.

1. Check/create issue before starting work
2. Reference in commits: `Closes #123` or `Ref #123`

## Multi-Agent Environment

Multiple agents share this local environment.

- **NEVER** `git add -A` or `git add .` — stages other agents' work
- **ALWAYS** `git add <specific-file>` — only files you modified
- Check `git status` before committing
- **NEVER** `git reset --hard`, `git checkout .`, `git restore .`, or `git clean -f` if untracked/modified files exist that you didn't create — destroys other agents' in-progress work
- Before any destructive git op: run `git status`, confirm ALL listed changes are yours. If unsure, **stop and ask user**

## Secrets

> **If in doubt, DON'T.**

### No secrets in public artifacts

Never put IPs, CIDRs, or network details in issues, commits, or PRs. Use generic descriptions ("hardcoded IPs") and reference file paths instead. IPs in local commands (kubectl, talosctl) are fine.

### Forbidden commands

**Secret extraction — NEVER run:**

- `kubectl get secret <name> -o yaml|json|jsonpath|--output=<any>`
- `sops -d <file>`
- `echo "$SECRET"`, `printenv VAR`, `env | grep`
- Reading `*.sops.yaml` or `talos/clusterconfig/*`

**kubectl exec — NEVER cat/read:**

- `/var/run/secrets/*`, `/etc/secrets/*`
- Files matching `*secret*`, `*token*`, `*password*`, `*credential*`, `*key*`, `*.pem`
- `env` or `printenv` inside pods

**Env vars — NEVER display values:**

- List keys only: `env | cut -d= -f1`
- Check existence: `test -n "${VAR+x}" && echo "set"`
- Sensitive key patterns (PASSWORD, SECRET, TOKEN, KEY, CREDENTIAL, API, AUTH): never echo

### Ceph — NEVER delete/blacklist/purge

Data loss is permanent and cascading.

**Forbidden:**

- `rbd rm|trash mv|snap purge <pool>/<image>`
- `ceph osd blocklist|blacklist add <addr>`
- `ceph osd pool delete <pool>`
- `kubectl delete pv <name>`

**Before ANY Ceph state change:**

1. Verify no watchers: `rbd status <pool>/<image>`
2. Verify no bound PVC: `kubectl get pv <name>`
3. Never force-remove "stuck" PVs — investigate root cause
4. Ask user before Ceph toolbox exec that modifies state

### Safe alternatives

| Instead of            | Do                                           |
| --------------------- | -------------------------------------------- |
| Reading secret values | `kubectl get secret <name>` (existence only) |
| Counting secret keys  | `-o json \| jq '.data \| keys'`              |
| Verifying secret data | `-o json \| jq '.data \| length'`            |
| Debugging auth        | Check pod logs, not secret contents          |

### SOPS

- Never decrypt via CLI
- User edits manually with `sops <file>`
- Read encrypted file for key names only
