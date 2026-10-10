# Constraints

## Work Requirements

A change needs a linked GitHub issue when a validator will run on it (see `validation.md`), because validators post their reports there. Large or risky work gets one too. Changes on the qa-validator skip list in `validation.md`, and read-only work, do not; commit them with a clear message and no `Ref`.

Closing keywords in commits don't close issues in this repo: close it yourself with `gh issue close`, and never tell the user an issue will auto-close.

## Multi-Agent Environment

Multiple agents share this local environment.

- **NEVER** `git add -A` or `git add .` — stages other agents' work
- **ALWAYS** `git add <specific-file>` — only files you modified (SOPS files: see SOPS below)
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
- Printing or reading `talos/clusterconfig/*` (plaintext Talos secrets); passing the path to `talosctl validate` is fine

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

| Instead of               | Do                                                                                                                                                                                                                                |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reading secret values    | Check its effects: Flux Kustomization Ready at the commit (SOPS), `kubectl get externalsecret <name>` shows `SecretSynced` (ESO), consuming pods rolled (Reloader, or a manual restart) and their logs show the new setting works |
| Checking a secret exists | `kubectl get secret <name>` only where RBAC allows (existence, key count in `DATA`); Coder workspaces can't read secrets                                                                                                          |
| Listing secret keys      | Read the manifests that consume it (`secretKeyRef`, `envFrom`)                                                                                                                                                                    |
| Debugging auth           | Check pod logs, not secret contents                                                                                                                                                                                               |

### SOPS

- The user edits secrets manually with `sops <file>`
- Settings deny reading `*.sops.*` files; get key names from the manifests that consume them, or ask the user
- Hooks block any shell command that names a `*.sops.*` file, `git add` included. Stage one by its directory (`git add <dir>/`) once `git status` shows every change there is yours
