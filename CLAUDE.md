# CLAUDE.md

Talos Linux homelab GitOps repository.

## Constraints

1. **No Python scripts** - Use bash/Taskfile only
2. **No SOPS decryption** - Never decrypt secrets via CLI
3. **Automation first** - Use Flux, Terraform, Talos declarative configs
4. **Validation required** - Run `task dev-env:lint` before commits
5. **Use Taskfile** - Prefer `task` commands over raw CLI

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

- Auto-fetch docs for common tools (Flux, Kubernetes, Helm, Cilium, Traefik, Rook, etc.)
- Ask before resolving unfamiliar/niche libraries
- Match cluster versions when available
