# Constraints

> **Hard rules that must never be violated.**

## Work Requirements

> **All work requires a linked GitHub issue. No exceptions.**

1. Check if issue exists before starting work
2. Create issue if needed using template fields
3. Track issue number throughout work
4. Reference in commits: `Closes #123` or `Ref #123`

## Multi-Agent Environment

> **CRITICAL: Multiple agents may work in the same local environment simultaneously.**

- **NEVER use `git add -A` or `git add .`** - Stages other agents' uncommitted work
- **ALWAYS use `git add <specific-file>`** - Only stage files you modified
- **Check `git status` before committing** - Verify only your files are staged

## Secrets Handling

> **If in doubt, DON'T. Ask user before any command that might expose secrets.**

### Forbidden Actions

| Action                                      | Why Dangerous                        |
| ------------------------------------------- | ------------------------------------ |
| `kubectl get secret -o yaml`                | Outputs base64-encoded secrets       |
| `kubectl get secret -o jsonpath='{.data}'`  | Same as above                        |
| `sops -d <file>`                            | Decrypts to stdout                   |
| `echo "$SECRET" \| command`                 | Secrets appear in process list/logs  |
| `echo "$VAR"` or `printenv VAR`             | May expose secret env vars           |
| `env \| grep` or `printenv`                 | Lists all env vars including secrets |
| Reading `*.sops.yaml` files                 | Blocked in settings, don't try       |
| Reading `talos/clusterconfig/*`             | Contains machine secrets             |

### Ceph Destructive Operations

> **NEVER delete, blacklist, or purge Ceph/RBD resources. Data loss is permanent and cascading.**

| Action                                      | Why Dangerous                                              |
| ------------------------------------------- | ---------------------------------------------------------- |
| `rbd rm <pool>/<image>`                     | Permanently destroys volume data, no undo                  |
| `rbd trash mv <pool>/<image>`               | Moves image to trash, breaks mounted volumes               |
| `ceph osd blocklist add <addr>`             | Kills ALL RBD I/O from that node, crashes every mounted PV |
| `ceph osd blacklist add <addr>`             | Legacy alias for blocklist add, equally destructive        |
| `kubectl delete pv <name>`                  | Orphans or destroys backing RBD image depending on policy  |
| `rbd snap purge <pool>/<image>`             | Destroys all snapshots, breaks clones                      |
| `ceph osd pool delete <pool>`               | Destroys entire storage pool                               |

**Before ANY Ceph operation:**
1. **Verify no watchers**: `rbd status <pool>/<image>` — if watchers exist, volume is IN USE
2. **Verify no bound PVC**: `kubectl get pv <name>` — if Bound, a workload depends on it
3. **Never force-remove a "stuck" PV** — investigate why it's stuck, don't delete around it
4. **Ask user before any Ceph toolbox exec** that modifies state

### kubectl Secret Access

The allow list permits `kubectl:*` for operational flexibility, but you MUST NEVER:

**kubectl get secret output formats:**
- `kubectl get secret <name> -o yaml` - NEVER
- `kubectl get secret <name> -o json` - NEVER
- `kubectl get secret <name> -o jsonpath='{.data}'` - NEVER
- `kubectl get secret <name> --output=<any>` - NEVER

**kubectl exec reading secrets:**
- `kubectl exec <pod> -- cat /var/run/secrets/*` - NEVER
- `kubectl exec <pod> -- cat /etc/secrets/*` - NEVER
- `kubectl exec <pod> -- cat *secret*` - NEVER
- `kubectl exec <pod> -- cat *token*` - NEVER
- `kubectl exec <pod> -- cat *password*` - NEVER
- `kubectl exec <pod> -- cat *credential*` - NEVER
- `kubectl exec <pod> -- cat *key*` - NEVER (private keys)
- `kubectl exec <pod> -- cat *.pem` - NEVER
- `kubectl exec <pod> -- env` - NEVER (may show secret env vars)
- `kubectl exec <pod> -- printenv` - NEVER

### Environment Variables

**NEVER display environment variable values.** Always check keys first, then decide:

1. **List keys only**: `env | cut -d= -f1` or `printenv | cut -d= -f1`
2. **Check if key exists**: `test -n "${VAR+x}" && echo "VAR is set"`
3. **If key looks sensitive** (contains PASSWORD, SECRET, TOKEN, KEY, CREDENTIAL, API, AUTH): **DO NOT echo or display its value**

```text
# BAD: Displaying env var values
echo "$AUTHENTIK_SECRET_KEY"           - NEVER
printenv POSTGRES_PASSWORD             - NEVER
env | grep PASSWORD                    - NEVER (shows values)

# CORRECT: Check existence without values
env | cut -d= -f1 | grep -i password   - OK (keys only)
test -n "${DB_PASSWORD+x}" && echo "DB_PASSWORD is set"  - OK
```

### Safe Alternatives

| Instead of...                    | Do this...                                         |
| -------------------------------- | -------------------------------------------------- |
| Reading secret values            | Check existence: `kubectl get secret <name>`       |
| Counting secret keys             | `kubectl get secret <name> -o json \| jq '.data \| keys'` |
| Verifying secret has data        | `kubectl get secret <name> -o json \| jq '.data \| length'` |
| Checking if user exists          | Count entries, don't list names                    |
| Debugging auth issues            | Check pod logs, not secret contents                |

### SOPS File Handling

- **Never decrypt** SOPS files via CLI
- **Edit pattern**: Use `sops <file>` (opens encrypted editor) - user does this manually
- **View structure**: Read encrypted file to see key names (values are encrypted)
- **Create new**: User creates manually, Claude provides template with placeholders
