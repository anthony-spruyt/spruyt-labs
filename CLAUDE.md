# CLAUDE.md

Talos Linux homelab GitOps repository on bare metal. No SSH access - use `talosctl`, Flux, or Kubernetes APIs.

## Hard Rules

1. **No secrets output** - Never run commands that display credentials
2. **Declarative only** - No manual kubectl patches; use Flux, Terraform, Talos configs
3. **No git push** - User pushes manually (SSH passkey requires interactive auth)
4. **No git amend** - Always new commits
5. **No SOPS decrypt** - Never decrypt secrets via CLI
6. **No hardcoded domains** - Use `${EXTERNAL_DOMAIN}` substitution
7. **No reading live secrets** - Never `kubectl get secret -o yaml/jsonpath`
8. **Taskfile first** - Prefer `task` commands over raw CLI

## Secrets

- Never output credentials (access keys, passwords, tokens)
- Never `echo "$SECRET" | command` - secrets may appear in logs
- Never log secret values to stdout/stderr
- Check existence, not values: count users, verify resources exist
- Mount secrets as files, not env vars when possible

## Workflow

**Before commit (non-trivial changes):**

```bash
task dev-env:lint && git add -A && git commit -m "type(scope): message"
```

Skip linting for trivial changes (typos, single-line fixes, SOPS-only). Pre-commit hooks catch issues.

**Validation:** Always test changes - check logs, `kubectl rollout restart`, verify end state. Plans should include validation steps.

**Conventional commits:** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`

**After push:** Flux webhooks auto-reconcile - no manual `flux reconcile` needed.

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

```
cluster/apps/<namespace>/<app>/
├── app/
│   ├── kustomization.yaml
│   ├── release.yaml        # HelmRelease
│   ├── values.yaml         # Helm values
│   └── *-secrets.sops.yaml # Encrypted secrets
```

**Variable substitution:** `${EXTERNAL_DOMAIN}`, `${CLUSTER_ISSUER}`, `${TIMEZONE}`

**SOPS naming:** `<name>-secrets.sops.yaml` or `<name>.sops.yaml`

## Research Priority

1. **Context7** - Library/tool docs (always first)
   - Auto-fetch for: Flux, Kubernetes, Helm, Cilium, Traefik, Rook, Talos, etc.
   - Ask before resolving unfamiliar/niche libraries
   - Match cluster versions when available
2. **Codebase** - Grep, Glob, Read for existing patterns
3. **GitHub** - Use `gh` CLI or raw GitHub search for issues/PRs/code
   ```bash
   gh search issues "<error>" --repo <org>/<repo>
   gh issue view <number> --repo <org>/<repo>
   gh pr view <number> --repo <org>/<repo>
   gh search code "<pattern>" --repo <org>/<repo>
   ```
   For raw file content, use WebFetch with `https://raw.githubusercontent.com/...`
   For error messages, search upstream repo's issues first.
4. **WebFetch** - Official docs URLs only
5. **WebSearch** - Last resort

## Documentation

- [README.md](README.md) - Architecture overview
- [docs/rules/procedures.md](docs/rules/procedures.md) - Ingress, certificates
- [docs/](docs/) - Bootstrap, maintenance, DR runbooks

After completing tasks, review and update relevant docs for accuracy.
