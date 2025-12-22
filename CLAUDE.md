# CLAUDE.md

Talos Linux homelab GitOps repository.

## Constraints

1. **No Python scripts** - Use bash/Taskfile only
2. **No SOPS decryption** - Never decrypt secrets via CLI
3. **Automation first** - Use Flux, Terraform, Talos declarative configs
4. **Use Taskfile** - Prefer `task` commands over raw CLI
5. **No manual cluster changes** - Never use kubectl to modify cluster state directly (annotations, patches, etc). Use Flux reconciliation or rollout restarts only.
6. **No git push** - User will push manually (SSH with passkey requires interactive authentication)

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

1. **Context7** - For library/tool documentation
2. **Codebase search** (Grep, Glob, Read) - For existing patterns and implementations
3. **gh CLI** - For GitHub issues, PRs, and discussions
4. **WebFetch** - For specific URLs (docs, READMEs)
5. **WebSearch** - Last resort when other tools don't have the answer
