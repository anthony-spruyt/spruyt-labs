# CLAUDE.md

Talos Linux homelab GitOps repository.

## Constraints

1. **No Python scripts** - Use bash/Taskfile only
2. **No SOPS decryption** - Never decrypt secrets via CLI
3. **Automation first** - Use Flux, Terraform, Talos declarative configs
4. **Use Taskfile** - Prefer `task` commands over raw CLI
5. **No manual cluster changes** - Never use kubectl to modify cluster state directly (annotations, patches, etc). Use Flux reconciliation or rollout restarts only.
6. **No git push** - User will push manually (SSH with passkey requires interactive authentication)
7. **No git amend** - Never use `git commit --amend`. Always create new commits.
8. **No hardcoded domains** - Never hardcode the public domain. Always use `${EXTERNAL_DOMAIN}` variable for Flux substitution.
9. **No reading live secrets** - Never use `kubectl get secret -o yaml/jsonpath` to read secret values from the cluster.

## Secret Security

**CRITICAL - NEVER OUTPUT SECRETS:**

- **Never run commands that output credentials** - Commands like `ceph dashboard get-rgw-api-access-key`, `radosgw-admin user info`, or any command that returns access keys, secret keys, passwords, or tokens are FORBIDDEN.
- **Never echo secrets** - Don't use `echo "$SECRET" | command`. Secrets may appear in logs or process lists.
- **Never log secret values** - Avoid commands that might output secrets to stdout/stderr.
- **Use file-based secrets** - Mount secrets as files and read with `-i /path/to/secret` or `cat /path/to/secret`.
- **Use secretKeyRef sparingly** - Environment variables from secretKeyRef are visible in pod specs. Prefer volume mounts for sensitive data used in scripts.
- **Check existence, not values** - To verify credentials exist, check if secrets/users exist without outputting their values. Use commands that return counts, booleans, or names only.

## Commit Workflow

**Run linter before commit for non-trivial changes:**

```bash
task dev-env:lint   # Step 1: Run linter (skip for trivial changes)
git add -A          # Step 2: Stage changes
git commit -m "..." # Step 3: Commit
```

Skip linting for trivial changes (typos, single-line fixes, SOPS-only changes). Pre-commit hooks will catch issues regardless.

## Git Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New features
- `fix:` Bug fixes
- `chore:` Maintenance
- `docs:` Documentation
- `refactor:` Code restructuring

## Environment

- **Platform**: Talos Linux Kubernetes on bare metal
- **Access**: No SSH - use `talosctl`, Flux, or Kubernetes APIs
- **Config**: Talos in `talos/`, cloud in `infra/terraform/`

## Documentation

- [README.md](README.md) - Architecture, troubleshooting matrix
- [docs/rules/procedures.md](docs/rules/procedures.md) - Ingress, certificates, detailed procedures
- [docs/](docs/) - Runbooks (bootstrap, maintenance, DR)

## Context7

- **ALWAYS use Context7 BEFORE web search** for library/tool documentation
- Auto-fetch docs for common tools (Flux, Kubernetes, Helm, Cilium, Traefik, Rook, etc.)
- Ask before resolving unfamiliar/niche libraries
- Match cluster versions when available

## Research Priority

When researching or troubleshooting, use tools in this order:

1. **Context7** - For library/tool documentation and API references
2. **Codebase search** (Grep, Glob, Read) - For existing patterns and implementations
3. **gh CLI** - For GitHub issues, PRs, discussions, code, and error messages (use `gh search issues`, `gh search code`, `gh issue view`)
4. **WebFetch** - For specific URLs (official docs, READMEs) - NOT for GitHub content
5. **WebSearch** - Last resort when other tools don't have the answer

**GitHub Research Rules:**

- **NEVER use WebSearch or WebFetch for GitHub** - Always use `gh` CLI for GitHub issues, PRs, code, and discussions
- Use `gh search issues "<query>" --repo <org>/<repo>` for issues
- Use `gh search code "<query>" --repo <org>/<repo>` for code
- Use `gh issue view <number> --repo <org>/<repo>` for issue details
- Use `gh pr view <number> --repo <org>/<repo>` for PR details
- For raw file content, use WebFetch with `https://raw.githubusercontent.com/...`

For error messages, search the upstream repo's issues first: `gh search issues "<error message>" --repo <org>/<repo>`
