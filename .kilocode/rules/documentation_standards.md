# Documentation Standards

## Purpose

This rule establishes standards for documentation quality, completeness, and maintenance in the spruyt-labs repository. It ensures that all documentation is accurate, up-to-date, and follows consistent formatting and structure.

## Standards

### General Requirements

1. **Accuracy**: All documentation must reflect current repository state, configurations, and processes. Remove or update outdated information immediately.

2. **Completeness**: Documentation should cover all critical aspects of the system, including setup, operation, troubleshooting, and maintenance.

3. **Consistency**: Use the established runbook structure defined in the root README.md for all operational documentation.

4. **Accessibility**: Write documentation for the intended audience (platform engineers, operators) with appropriate technical depth.

### File and Directory Standards

1. **README.md Files**: Every component directory must have a README.md following the runbook template.

2. **Cross-references**: All links and references must be valid and point to existing files.

### Content Standards

1. **Version Information**: Keep version-specific details (Talos versions, Kubernetes versions, chart versions) current.

2. **Command Examples**: Provide working, tested command examples with proper syntax.

3. **Prerequisites**: Clearly document all required tools, permissions, and environmental conditions.

4. **Validation Steps**: Include specific validation commands and expected outcomes for all procedures.

5. **Agent-Friendly Workflows**: All runbooks must include decision trees and conditional logic for autonomous execution, specifying exact commands, expected outputs, and failure recovery steps.

### Maintenance Requirements

1. **Regular Reviews**: Review documentation quarterly or after major changes to ensure accuracy. Conduct audits to verify README presence in all component directories and update version-specific information.

2. **Broken Link Checks**: Run automated checks for broken internal references.

3. **Template Usage**: Use the provided README template for new documentation. For app components, populate the template with app-specific details including directory layout, operational procedures, validation steps, and troubleshooting guidance.

4. **App Documentation Prioritization**: Prioritize README creation for critical infrastructure components (cert-manager, external-secrets, ingress controllers) before user-facing applications.

5. **Agent-Driven Updates**: Agents must update rules and documentation immediately when invalid, outdated, or incorrect information is discovered during operations.

6. **New Feature Documentation**: When new features, components, or processes are added, agents must review and update relevant documentation and rules to ensure accuracy and completeness.

7. **Ongoing Maintenance Emphasis**: Documentation and rules must always be kept up to date to support autonomous operations.

## Enforcement

- Documentation changes must pass mega-linter checks
- Pull requests modifying documentation require review for compliance with these standards
- Missing or inadequate documentation blocks feature development until resolved
- App components (under `cluster/apps/`) must have README.md files; new apps require documentation before merge
- Automated checks should validate README presence in component directories

## Related Rules

- [kubernetes.md](kubernetes.md) — kubectl workflow guidelines
- [project_context.md](project_context.md) — project operating context
- [shared-procedures.md](shared-procedures.md) — common operational patterns
