# Documentation Standards

## Purpose

Practical documentation standards for the spruyt-labs homelab. Keep documentation accurate, simple, and maintainable.

## Code Block Standards

1. **Language identifiers required**: Use triple backticks with identifiers (`yaml`, `bash`, `json`)
2. **Consistent indentation**: 2 spaces for YAML, 4 spaces for JSON
3. **Line length**: Max 120 characters for readability
4. **No raw code**: All commands and configs must be in code blocks

Example:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: example
```

```bash
kubectl get pods -n default
```

## General Requirements

1. **Accuracy**: Documentation must reflect current state - update immediately when things change
2. **Completeness**: Cover setup, operation, and basic troubleshooting
3. **Consistency**: Follow the README template for all components
4. **Simplicity**: Homelab-appropriate - practical and maintainable

## Content Standards

1. **Command examples**: Tested, working commands
2. **Prerequisites**: Tools, permissions, and dependencies
3. **Validation steps**: Commands with expected outcomes
4. **Troubleshooting**: Common issues with symptoms and resolutions

## Accuracy Requirements

1. **Component names**: Must match exactly what's in release.yaml and Helm chart
2. **Namespaces**: Must match ks.yaml targetNamespace
3. **Dependencies**: Must list actual dependencies from ks.yaml dependsOn
4. **GitOps-first**: Procedures should prefer editing manifests and reconciling over manual kubectl apply

> **Note**: Directory layouts are not required in individual READMEs. The standard structure is documented in `cluster/apps/README.md`.

## Maintenance

1. **Review after changes**: Update docs when repository changes affect accuracy
2. **Use template**: Start new docs from `docs/templates/readme_template.md`
3. **Validate before commit**: Run `task dev-env:lint`

## Validation

### Automated

```bash
task dev-env:lint
# Expected: No linting errors, no broken links
```

### Manual Checklist

- [ ] All links point to existing files
- [ ] Command examples are tested
- [ ] Prerequisites documented
- [ ] Code blocks have language identifiers
- [ ] Follows README template structure

## Enforcement

- All documentation changes must pass `task dev-env:lint`
- New app components require README.md before merge
- Code blocks must have proper language identifiers

## Related

- [core_rules.md](core_rules.md) - Operational constraints
- [procedures.md](procedures.md) - Common operational patterns
