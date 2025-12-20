# Core Rules for Spruyt-labs Homelab

## Purpose

Core operational standards and constraints for the homelab. For full documentation, see [README.md](../../README.md).

## Environment

- **Platform**: Talos Linux Kubernetes on bare metal
- **Access**: No SSH - use `talosctl`, Flux, or Kubernetes APIs
- **Config**: Talos in `talos/`, cloud in `infra/terraform/`

## Constraints

1. **No Python scripts** - Use bash/Taskfile only
2. **No SOPS decryption** - Never decrypt secrets via CLI
3. **Automation first** - Use Flux, Terraform, Talos declarative configs
4. **Validation required** - Run `task dev-env:lint` before commits
5. **Use Taskfile** - Prefer `task` commands over raw CLI

## Git Conventions

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commits and PRs:

- `feat:` - New features
- `fix:` - Bug fixes
- `chore:` - Maintenance tasks
- `docs:` - Documentation changes
- `refactor:` - Code restructuring
- `test:` - Test additions/changes

## Quick Reference

### Validation

```bash
task dev-env:lint          # Lint all files
task terraform:fmt         # Format Terraform
task terraform:validate    # Validate Terraform
```

### Kubernetes

```bash
kubectl api-resources                           # List resource types
kubectl explain <resource> --recursive          # Show resource fields
kubectl get <type> -n <ns> -o yaml              # Get live manifest
```

### Flux

```bash
flux get kustomizations -A                      # All kustomizations
flux reconcile kustomization <name> --with-source  # Force reconcile
flux get helmreleases -n <ns>                   # HelmRelease status
```

### Error Recovery

```bash
# RBAC issues
kubectl auth can-i <verb> <resource>

# Flux rollback
flux suspend kustomization <name>
# (revert commit)
flux reconcile kustomization <name> --with-source

# Helm rollback
helm rollback <release> <revision> -n <ns>
```

## Workflow

1. Plan changes (review docs)
2. Use `task` commands
3. Validate with `task dev-env:lint`
4. Commit and let Flux reconcile
5. **Verify deployment** - Always confirm changes are healthy before continuing:
   - `flux get kustomizations -A` - Check reconciliation status
   - `kubectl get pods -n <ns>` - Verify pods are running
   - Check logs if issues: `kubectl logs -n <ns> -l app.kubernetes.io/name=<app>`

## Related

- [README.md](../../README.md) - Full documentation
- [procedures.md](procedures.md) - Detailed procedures
- [documentation.md](documentation.md) - Doc standards
