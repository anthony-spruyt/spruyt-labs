# Secrets Handling

> **If in doubt, DON'T. Ask user before any command that might expose secrets.**

## Forbidden Actions

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

## kubectl Secret Access

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

## Environment Variables

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

## Safe Alternatives

| Instead of...                    | Do this...                                         |
| -------------------------------- | -------------------------------------------------- |
| Reading secret values            | Check existence: `kubectl get secret <name>`       |
| Counting secret keys             | `kubectl get secret <name> -o json \| jq '.data \| keys'` |
| Verifying secret has data        | `kubectl get secret <name> -o json \| jq '.data \| length'` |
| Checking if user exists          | Count entries, don't list names                    |
| Debugging auth issues            | Check pod logs, not secret contents                |

## SOPS File Handling

- **Never decrypt** SOPS files via CLI
- **Edit pattern**: Use `sops <file>` (opens encrypted editor) - user does this manually
- **View structure**: Read encrypted file to see key names (values are encrypted)
- **Create new**: User creates manually, Claude provides template with placeholders
