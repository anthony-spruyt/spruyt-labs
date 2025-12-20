# CLAUDE.md

Guidance for Claude Code working with this Talos Linux homelab GitOps repository.

## Constraints

1. **No Python scripts** - Strictly prohibited for automation
2. **No SSH access** - Use talosctl, Flux, or Kubernetes APIs only
3. **Validation required** - Run `task dev-env:lint` before commits
4. **Use Taskfile** - Prefer `task` commands over raw CLI

## Quick Commands

```bash
task --list                    # All available tasks
task dev-env:lint              # Lint before commit
flux get kustomizations -A     # Check reconciliation
talosctl health                # Cluster health
```

## Documentation

- **Full docs**: [README.md](README.md)
- **Architecture**: [README.md#architecture](README.md#architecture)
- **Troubleshooting**: [README.md#troubleshooting-matrix](README.md#troubleshooting-matrix)
- **App layout**: `cluster/apps/<namespace>/<app>/`
