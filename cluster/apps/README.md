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
3. **Decision Trees**: Include YAML decision trees for autonomous operations
4. **Cross-Service Dependencies**: Document key inter-service relationships
5. **MCP Integration**: Include Context7 library usage patterns

### Procedures

1. **Creating New Documentation**:

   - Use the provided README template
   - Populate required sections with accurate information
   - Add agent-friendly workflows and decision trees
   - Include basic monitoring commands

2. **Updating Existing Documentation**:

   - Review for accuracy and completeness
   - Update outdated information and versions
   - Add missing elements (decision trees, dependencies)
   - Verify all cross-references are valid

3. **Validation**:
   - Run `task dev-env:lint` for automated checks
   - Verify YAML syntax in decision trees
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

- [Documentation Standards](../../.kilocode/rules/documentation_rules.md)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Markdown Guide](https://www.markdownguide.org/)

## Agent-Friendly Workflows

### Documentation Health Check Workflow

```yaml
# Documentation health check decision tree
start: "check_documentation_completeness"
nodes:
  check_documentation_completeness:
    question: "Are all required README.md files present?"
    command: 'find cluster/apps -type d -depth 2 | xargs -I {} sh -c ''test -f {}/README.md || echo "Missing: {}"'' | wc -l'
    validation: "grep -q '^0$'"
    yes: "check_linting"
    no: "create_missing_readmes"
  check_linting:
    question: "Does documentation linting pass?"
    command: "task dev-env:lint 2>&1 | grep -E '(error|Error|ERROR)' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_decision_trees"
    no: "fix_linting_errors"
  check_decision_trees:
    question: "Are all decision trees valid YAML?"
    command: "find cluster/apps -name README.md -exec sh -c 'grep -q \"start:\" \"$1\" && yq eval . \"$1\" > /dev/null 2>&1 && echo OK || echo FAIL' _ {} \\; | grep -c FAIL"
    validation: "grep -q '^0$'"
    yes: "check_links"
    no: "fix_yaml_syntax"
  check_links:
    question: "Are all internal links valid?"
    command: "task dev-env:lint 2>&1 | grep -i 'broken\\|invalid' | wc -l"
    validation: "grep -q '^0$'"
    yes: "documentation_healthy"
    no: "fix_broken_links"
  create_missing_readmes:
    action: "Create missing README.md files using the established template"
    next: "check_documentation_completeness"
  fix_linting_errors:
    action: "Fix linting errors in documentation files"
    next: "check_linting"
  fix_yaml_syntax:
    action: "Fix YAML syntax errors in decision trees"
    next: "check_decision_trees"
  fix_broken_links:
    action: "Fix or remove broken internal links"
    next: "check_links"
  documentation_healthy:
    action: "Documentation is complete, valid, and healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../.kilocode/context7-libraries.json)
- Confirm the catalog entry contains needed documentation patterns
- Note the library identifier and version information

### When the catalog covers documentation needs

1. Use information from [`context7-libraries.json`](../../.kilocode/context7-libraries.json)
2. Record library ID and relevant snippets in change notes
3. Mention how the material informed documentation changes

### When documentation is missing or outdated

1. Run `resolve-library-id` with precise description of needed documentation
2. If no match, escalate to documentation governance contact
3. Once new library added, update worklogs with new ID

### Documenting Citations and MCP Usage

- Capture tool used, timestamp, and output summary in change notes
- Include links or excerpts where practical
- Call out any assumptions made when interpreting documentation
