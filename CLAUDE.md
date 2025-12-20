# CLAUDE.md

Guidance for Claude Code working with this Talos Linux homelab GitOps repository.

## Constraints

1. **No Python scripts** - Strictly prohibited for automation
2. **No SSH access** - Use talosctl, Flux, or Kubernetes APIs only
3. **No SOPS decryption** - Never decrypt secrets via CLI or sops tasks
4. **Validation required** - Run `task dev-env:lint` before commits
5. **Use Taskfile** - Prefer `task` commands over raw CLI

## Available CLI Tools

The devcontainer includes these pre-installed tools for cluster operations:

- **kubectl** - Kubernetes CLI for cluster management
- **helm** - Kubernetes package manager
- **flux** - GitOps toolkit CLI
- **talosctl** - Talos Linux node management
- **velero** - Backup and restore CLI
- **cilium** - CNI CLI for network debugging
- **hubble** - Cilium network observability CLI
- **sops** - Secret encryption/decryption
- **kustomize** - Kubernetes manifest customization
- **terraform** - Infrastructure as code

## Quick Commands

```bash
task --list                    # All available tasks
task dev-env:lint              # Lint before commit
flux get kustomizations -A     # Check reconciliation
talosctl health                # Cluster health
kubectl get pods -A            # List all pods
kubectl rollout restart deploy/<name> -n <ns>  # Restart deployment
```

## Documentation

- **Full docs**: [README.md](README.md)
- **Architecture**: [README.md#architecture](README.md#architecture)
- **Troubleshooting**: [README.md#troubleshooting-matrix](README.md#troubleshooting-matrix)
- **App layout**: `cluster/apps/<namespace>/<app>/`

## Git Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commits and PRs:
`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`
