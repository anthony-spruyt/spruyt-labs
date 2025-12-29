# CLAUDE.md

Talos Linux homelab GitOps repository on bare metal. No SSH access - use `talosctl`, Flux, or Kubernetes APIs.

## Research Priority (ALWAYS FOLLOW THIS ORDER)

> **NEVER skip steps. NEVER use WebSearch before exhausting other options.**

| Step | Tool         | Use For                | Example                                            |
| ---- | ------------ | ---------------------- | -------------------------------------------------- |
| 1    | **Context7** | Library/tool docs      | `resolve-library-id` → `get-library-docs`          |
| 2    | **GitHub**   | Issues, PRs, code      | `gh search issues "error" --repo org/repo`         |
| 3    | **Codebase** | Existing patterns      | Grep, Glob, Read                                   |
| 4    | **WebFetch** | Official docs URLs     | raw.githubusercontent.com, allowed docs.\* domains |
| 5    | **WebSearch**| LAST RESORT ONLY       | Only after steps 1-4 fail                          |

### Research Decision Flow

1. **Library/tool question?** → Context7 first (`resolve-library-id`)
   - Found → `get-library-docs`
   - Not found → proceed to step 2
2. **Has GitHub repo?** → `gh` CLI
   - `gh search issues "topic" --repo org/repo`
   - `gh issue list --repo org/repo --search "topic"`
   - For raw files: WebFetch `raw.githubusercontent.com/...`
3. **Official docs URL known?** → WebFetch (allowed domains only)
4. **All above failed?** → WebSearch (state why others failed first)

### Context7 Auto-Fetch Criteria

Auto-fetch (no need to ask):

- Core infrastructure: Flux, Kubernetes, Helm, Cilium, Traefik, Rook, Talos
- Deployed in cluster: check `cluster/apps/` for what's installed
- Common DevOps tools: Terraform, Ansible, cert-manager, external-dns

Ask before resolving:

- Niche/unfamiliar libraries
- Ambiguous names (multiple projects with same name)
- Tools not in above categories

### When Context7 Doesn't Have the Library

1. Check GitHub → `gh issue list --repo org/repo --search "topic"`
2. Fetch README → WebFetch `raw.githubusercontent.com/.../README.md`
3. Only then → WebSearch, explaining: "Context7 and GitHub don't have X, using web search"

### Wrong vs Correct Research Pattern

```text
# BAD: Jumping to WebSearch
User: "Does Technitium support SSO?"
Wrong: WebSearch("Technitium SSO")  ← NEVER do this first

# CORRECT:
1. Context7: resolve-library-id("Technitium")  ← Not found
2. GitHub: gh issue list --repo TechnitiumSoftware/DnsServer --search "SSO"
3. WebFetch: raw.githubusercontent.com/.../README.md
4. WebSearch: Only if all above fail
```

## Hard Rules

1. **No secrets output** - Never run commands that display credentials or env var values
2. **No env var values** - Never `echo $VAR`, `printenv`, or `env | grep` - list keys only
3. **Declarative only** - No manual kubectl patches; use Flux, Terraform, Talos configs
4. **No git push** - User pushes manually (SSH passkey requires interactive auth)
5. **No git amend** - Always new commits
6. **No SOPS decrypt** - Never decrypt secrets via CLI
7. **No hardcoded domains** - Use `${EXTERNAL_DOMAIN}` substitution
8. **No reading live secrets** - Never `kubectl get secret -o yaml/jsonpath`
9. **Taskfile first** - Prefer `task` commands over raw CLI
10. **Explicit git add** - Only stage files YOU explicitly changed; NEVER use `git add -A` or `git add .`

## Secrets (NEVER EXPOSE)

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

> **CRITICAL - kubectl secret access:**
> The allow list permits `kubectl:*` for operational flexibility, but you MUST NEVER:
>
> **kubectl get secret output formats:**
>
> - `kubectl get secret <name> -o yaml` ← NEVER
> - `kubectl get secret <name> -o json` ← NEVER
> - `kubectl get secret <name> -o jsonpath='{.data}'` ← NEVER
> - `kubectl get secret <name> --output=<any>` ← NEVER
>
> **kubectl exec reading secrets:**
>
> - `kubectl exec <pod> -- cat /var/run/secrets/*` ← NEVER
> - `kubectl exec <pod> -- cat /etc/secrets/*` ← NEVER
> - `kubectl exec <pod> -- cat *secret*` ← NEVER
> - `kubectl exec <pod> -- cat *token*` ← NEVER
> - `kubectl exec <pod> -- cat *password*` ← NEVER
> - `kubectl exec <pod> -- cat *credential*` ← NEVER
> - `kubectl exec <pod> -- cat *key*` ← NEVER (private keys)
> - `kubectl exec <pod> -- cat *.pem` ← NEVER
> - `kubectl exec <pod> -- env` ← NEVER (may show secret env vars)
> - `kubectl exec <pod> -- printenv` ← NEVER
>
> **Safe alternatives:**
>
> - `kubectl get secret <name>` (shows metadata only)
> - `kubectl get secret <name> -o json | jq '.data | keys'` (key names only)
> - `kubectl exec <pod> -- ls /path` (list files, don't read)
> - `kubectl exec <pod> -- env | cut -d= -f1` (env var names only)

### Environment Variables

**NEVER display environment variable values.** Always check keys first, then decide:

1. **List keys only**: `env | cut -d= -f1` or `printenv | cut -d= -f1`
2. **Check if key exists**: `test -n "${VAR+x}" && echo "VAR is set"`
3. **If key looks sensitive** (contains PASSWORD, SECRET, TOKEN, KEY, CREDENTIAL, API, AUTH): **DO NOT echo or display its value**

```text
# BAD: Displaying env var values
echo "$AUTHENTIK_SECRET_KEY"           ← NEVER
printenv POSTGRES_PASSWORD             ← NEVER
env | grep PASSWORD                    ← NEVER (shows values)

# CORRECT: Check existence without values
env | cut -d= -f1 | grep -i password   ← OK (keys only)
test -n "${DB_PASSWORD+x}" && echo "DB_PASSWORD is set"  ← OK
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

### Wrong vs Correct Secret Pattern

```text
# BAD: Exposing secret values
kubectl get secret postgres-creds -o yaml        ← NEVER
kubectl get secret postgres-creds -o jsonpath='{.data.password}' | base64 -d  ← NEVER

# CORRECT: Check existence without values
kubectl get secret postgres-creds                ← OK (just shows name/type/age)
kubectl get secret postgres-creds -o json | jq '.data | keys'  ← OK (shows key names only)
kubectl get secret postgres-creds -o json | jq '.data | length'  ← OK (count of keys)
```

## CLI Tool Preferences

Use Claude's native tools instead of shell commands when possible:

| Task           | Preferred            | Avoid                 |
| -------------- | -------------------- | --------------------- |
| Read files     | `Read` tool          | `cat`, `head`, `tail` |
| Search content | `Grep` tool          | `grep`, `rg`          |
| Find files     | `Glob` tool          | `find`, `ls -R`       |
| Edit files     | `Edit` tool          | `sed -i`, `awk -i`    |
| List env keys  | `env \| cut -d= -f1` | `env`, `printenv`     |

**Note:** `echo` and `cat` are not in the allow list to prevent accidental
`echo $SECRET` or `cat /path/to/secret`. Use the Read tool for file contents.

## Workflow

**Before commit (non-trivial changes):**

```bash
task dev-env:lint && git add <specific-files> && git commit -m "type(scope): message"
```

Skip linting for trivial changes (typos, single-line fixes, SOPS-only). Pre-commit hooks catch issues.

**Conventional commits:** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`

**After push:** Flux webhooks auto-reconcile - no manual `flux reconcile` needed.

### Multi-Agent Environment

> **CRITICAL: Multiple agents may work in the same local environment simultaneously.**

- **NEVER use `git add -A` or `git add .`** - This will stage other agents' uncommitted work
- **ALWAYS use `git add <specific-file>`** - Only stage files you explicitly modified
- **Check `git status` before committing** - Verify only your files are staged
- If you accidentally commit another agent's files, the damage may be irreversible

```text
# BAD: Stages everything including other agents' work-in-progress
git add -A
git add .

# CORRECT: Stage only the files you changed
git add cluster/apps/myapp/values.yaml
git add cluster/apps/myapp/release.yaml
```

## Validation Agents (MANDATORY)

> **Use these agents automatically - do NOT wait for user to request them.**

| Agent | When to Use | Trigger |
|-------|-------------|---------|
| **qa-validator** | Before ANY git commit that modifies cluster resources | After editing HelmRelease, Kustomization, values.yaml, or K8s manifests |
| **cluster-validator** | After user pushes to main | When user says "pushed", "merged", or "deployed" |

### Validation Flow

```text
1. Make code changes
2. ALWAYS run qa-validator (before commit)
3. If BLOCKED → apply fixes → re-run qa-validator
4. If APPROVED → commit
5. User pushes
6. ALWAYS run cluster-validator (after push)
7. If ROLLBACK → revert commit → user pushes → re-run cluster-validator
8. If ROLL-FORWARD → apply fix → commit → user pushes → re-run cluster-validator
```

### When to Skip Validation Agents

- **qa-validator**: Only skip for docs-only changes (*.md files) or SOPS-only changes
- **cluster-validator**: Only skip if changes don't affect cluster state (pure docs)

## Validation (MANDATORY)

**After EVERY change that affects cluster state, you MUST validate:**

1. **Wait for reconciliation** - Check pod/deployment status after Flux syncs
2. **Verify the change worked** - Run kubectl commands to confirm expected state
3. **Check logs for errors** - Look at relevant pod logs for issues
4. **Report results to user** - Don't just say "done", show proof it worked

**Validation examples:**

```bash
# After HelmRelease change
kubectl get hr -n <namespace> <release>
kubectl get pod -n <namespace> -l app=<app>
kubectl logs -n <namespace> -l app=<app> --tail=20

# After config change
kubectl exec <pod> -- <verify-command>
```

**Never skip validation.** If user says "pushed", immediately check reconciliation status and verify the change took effect. Plans must include specific validation steps.

## Codebase Map

| Path                       | Purpose                      |
| -------------------------- | ---------------------------- |
| `cluster/apps/<ns>/<app>/` | Application deployments      |
| `cluster/flux/meta/`       | Flux config, cluster secrets |
| `talos/`                   | Talos machine configs        |
| `infra/terraform/`         | Cloud infrastructure         |
| `.taskfiles/`              | Automation scripts           |
| `docs/`                    | Runbooks                     |

## Patterns

**App structure:**

```text
cluster/apps/<namespace>/
├── namespace.yaml          # Namespace with PSA labels
├── kustomization.yaml      # References namespace + app ks.yaml files
├── <app>/                  # Single app
│   ├── ks.yaml
│   ├── app/
│   │   ├── kustomization.yaml
│   │   ├── release.yaml        # HelmRelease
│   │   ├── values.yaml         # Helm values
│   │   └── *-secrets.sops.yaml # Encrypted secrets
│   └── <optional>/         # Optional dependent resources (e.g., ingress/)
├── <app1>/                 # Multiple apps (e.g., operator + instance)
│   ├── ks.yaml
│   └── app/
└── <app2>/
    ├── ks.yaml
    └── app/
```

**Multiple Kustomizations for dependent resources:**

When an app has optional resources that depend on it (e.g., ingress routes), add multiple
Kustomizations in the same `ks.yaml`:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
spec:
  path: ./cluster/apps/<namespace>/<app>/app
  ...
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp-ingress
spec:
  path: ./cluster/apps/<namespace>/<app>/ingress
  dependsOn:
    - name: myapp
    - name: other-dependency
  ...
```

**Variable substitution:** `${EXTERNAL_DOMAIN}`, `${CLUSTER_ISSUER}`, `${TIMEZONE}`

**SOPS naming:** `<name>-secrets.sops.yaml` or `<name>.sops.yaml`

**Helm values:** Before modifying Helm values, ALWAYS check upstream/source values.yaml first:

- Use Context7 or WebFetch with raw.githubusercontent.com to find correct key paths
- Never assume key names
- Verify the chart version matches when checking upstream docs

## Documentation

- [README.md](README.md) - Architecture overview
- [docs/rules/core_rules.md](docs/rules/core_rules.md) - Core operational standards
- [docs/rules/documentation.md](docs/rules/documentation.md) - Documentation standards
- [docs/rules/procedures.md](docs/rules/procedures.md) - Ingress, certificates
- [docs/rules/renovate.md](docs/rules/renovate.md) - Renovate config, testing, troubleshooting
- [docs/intel-hybrid-architecture.md](docs/intel-hybrid-architecture.md) - P-core/E-core tuning, IRQ balance
- [docs/](docs/) - Bootstrap, maintenance, DR runbooks

After completing tasks, review and update relevant docs for accuracy.
