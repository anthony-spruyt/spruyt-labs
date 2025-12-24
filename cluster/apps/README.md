# Cluster Applications Documentation

## Overview

This document provides guidelines and standards for application documentation within the `cluster/apps/` directory. It establishes practical, maintainable documentation practices suitable for a homelab environment with agentic support.

## Directory Layout

```yaml
cluster/apps/
├── <namespace>/
│   ├── kustomization.yaml          # Namespace-level Kustomization
│   ├── namespace.yaml              # Namespace definition (optional)
│   ├── <app>/
│   │   ├── ks.yaml                 # Flux Kustomization
│   │   ├── README.md               # Component documentation
│   │   └── app/
│   │       ├── kustomization.yaml  # Kustomize configuration
│   │       ├── release.yaml        # HelmRelease definition
│   │       ├── values.yaml         # Chart values
│   │       └── kustomizeconfig.yaml # Kustomize config (optional)
└── README.md                       # This file
```

## Prerequisites

- Familiarity with Flux CD and GitOps workflows
- Basic Kubernetes knowledge (kubectl, Helm)
- Understanding of the homelab infrastructure
- Access to the repository and cluster

## Operation

### Documentation Standards

1. **Structure**: Follow the established template with required sections
2. **Code Blocks**: Use proper language identifiers for all code examples
3. **Accuracy**: Content must match actual ks.yaml, release.yaml, and values.yaml

### Procedures

1. **Creating New Documentation**:

   - Populate required sections with accurate information
   - Include key monitoring and troubleshooting commands

2. **Updating Existing Documentation**:

   - Review for accuracy against actual configuration
   - Update outdated information and versions
   - Verify all cross-references are valid

3. **Validation**:
   - Run `task dev-env:lint` for automated checks
   - Check for broken links and references
   - Ensure code blocks have proper language identifiers

## Troubleshooting

### Common Issues

1. **Documentation Drift**:

   - **Symptom**: Documentation doesn't match current state
   - **Diagnosis**: Compare with actual cluster configuration
   - **Resolution**: Update documentation to reflect current reality

2. **Broken References**:

   - **Symptom**: Links to non-existent files or resources
   - **Diagnosis**: Run link validation checks
   - **Resolution**: Fix or remove broken references

3. **Missing Sections**:
   - **Symptom**: Required sections not present
   - **Diagnosis**: Review against documentation standards
   - **Resolution**: Add missing sections following template

## Maintenance

### Updates

```bash
# Validate all documentation
task dev-env:lint

# Check for missing README files
find cluster/apps -type d -depth 2 | xargs -I {} sh -c 'test -f {}/README.md || echo "Missing README: {}"'

# Update documentation references
grep -r 'version:' cluster/apps/ | head -10
```

### Documentation Audit

```bash
# Find missing README files
for dir in cluster/apps/*/*/; do
  test -f "$dir/README.md" && echo "Checking $dir" || echo "Missing $dir/README.md"
done

# Validate structure
task documentation:validate
```

## References

- [Documentation Standards](../../docs/rules/documentation.md)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Markdown Guide](https://www.markdownguide.org/)
