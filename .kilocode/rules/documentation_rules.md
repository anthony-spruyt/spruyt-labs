# Documentation Standards

## Purpose

This rule establishes practical standards for documentation quality, completeness, and maintenance in the spruyt-labs homelab repository. It ensures that all documentation is accurate, up-to-date, and follows consistent formatting while being maintainable for a homelab environment with agentic support.

## Code Block Standards

### Code Block Requirements

All code examples, YAML configurations, command examples, and any language-specific content must be properly formatted within backtick code blocks with appropriate language identifiers.

1. **Proper Code Block Formatting**: All code must be enclosed in triple backticks (```) with language identifiers
2. **Language Identifiers**: Use appropriate language identifiers such as `yaml`, `bash`, `sh`, `json`, etc.
3. **No Raw Code**: No code should appear outside of properly formatted code blocks
4. **Consistent Formatting**: Maintain consistent indentation (2 spaces for YAML, 4 spaces for JSON) within code blocks
5. **Review Requirements**: Reviewers must check for and correct improper code block usage
6. **Line Length**: Code lines should not exceed 120 characters for readability

### Code Block Validation Commands

````bash
# Validate all code blocks have proper language identifiers
grep -r '```[^a-z]' . --include="*.md" || echo "Found code blocks without language identifiers"

# Check for raw code outside code blocks
grep -r '^[[:space:]]*[^`#]' . --include="*.md" | grep -E '(kubectl|helm|flux|apiVersion|kind:)' || echo "Found potential raw code"
````

### Examples of Proper Code Block Usage

```yaml
# Proper YAML code block example with consistent 2-space indentation
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
  labels:
    app: demo
    tier: frontend
spec:
  containers:
    - name: nginx
      image: nginx:latest
      ports:
        - containerPort: 80
          protocol: TCP
```

```bash
# Proper bash command example with clear comments
kubectl get pods -n default --no-headers | grep 'Running'

# Multi-line command example
kubectl get pods -n default -o json | \
  jq '.items[] | {name: .metadata.name, status: .status.phase}'
```

```json
# Proper JSON code block example with consistent 4-space indentation
{
    "name": "example",
    "version": "1.0.0",
    "dependencies": [
        {
            "name": "lodash",
            "version": "^4.17.21"
        }
    ],
    "scripts": {
        "start": "node index.js",
        "test": "jest"
    }
}
```

## Standards

### General Requirements

1. **Accuracy**: All documentation must reflect current repository state, configurations, and processes. Remove or update outdated information immediately.
2. **Completeness**: Documentation should cover critical aspects of the system, including setup, operation, and basic troubleshooting.
3. **Consistency**: Use the established runbook structure defined in the root README.md for operational documentation.
4. **Simplicity**: Write documentation appropriate for a homelab environment - practical and maintainable.
5. **Agentic Optimization**: All documentation must be optimized for autonomous execution with decision trees and machine-readable elements suitable for homelab scale.

### File and Directory Standards

1. **README.md Files**: Every component directory should have a README.md following a practical template with agentic workflows suitable for homelab.
2. **Cross-references**: All links and references should be valid and point to existing files.
3. **Decision Tree Coverage**: Components should include YAML decision trees for autonomous operations at homelab scale.

### Content Standards

1. **Version Information**: Keep version-specific details (Talos versions, Kubernetes versions) current, but don't over-document app versions.
2. **Command Examples**: Provide working, tested command examples with proper syntax, following the [Code Block Requirements](#code-block-requirements).
3. **Prerequisites**: Clearly document required tools, permissions, and environmental conditions.
4. **Validation Steps**: Include specific validation commands and expected outcomes for all procedures.
5. **Agent-Friendly Workflows**: All runbooks must include decision trees and conditional logic for autonomous execution, specifying exact commands, expected outputs, and failure recovery steps suitable for homelab.
6. **Basic Monitoring**: Include simple monitoring commands for critical components.
7. **Cross-Service Dependencies**: Document key inter-service dependencies with basic health check commands.
8. **MCP Integration**: Include Context7 library usage patterns with citation workflows and escalation procedures appropriate for homelab scale.
9. **Code Block Compliance**: All code examples, configurations, and command examples must follow the [Code Block Requirements](#code-block-requirements) for proper formatting and language identification.

### Maintenance Requirements

1. **Regular Reviews**: Review documentation periodically or after major changes to ensure accuracy.
2. **Broken Link Checks**: Run basic checks for broken internal references.
3. **Template Usage**: Use the provided README template for new documentation.
4. **Agent-Driven Updates**: Update rules and documentation when invalid or outdated information is discovered during operations.
5. **Practical Updates**: Keep documentation practical and useful for homelab operations.

## Procedures

### Creating New Documentation

1. **Identify Requirement**: Determine if new documentation is needed based on new features or components.
2. **Use Template**: Start with the established README template from the root README.md.
3. **Populate Sections**: Fill in required sections with accurate, current information.
4. **Add Agent-Friendly Elements**: Include decision trees, command templates, and structured metadata suitable for homelab.
5. **Add Monitoring Commands**: Define basic monitoring commands.
6. **Document Dependencies**: Map key cross-service dependencies with health check commands.
7. **Integrate MCP Usage**: Add Context7 library usage patterns and citation workflows.
8. **Validate**: Run validation checks before committing.

### Updating Existing Documentation

1. **Monitor Changes**: Track repository changes that affect documentation accuracy.
2. **Update Content**: Modify outdated information, versions, or procedures.
3. **Add Missing Elements**: Ensure agent-friendly workflows and validation steps are present.
4. **Review Links**: Verify all cross-references are valid.
5. **Enhance Decision Trees**: Add new failure scenarios and recovery paths as needed.
6. **Validate**: Run validation checks before committing.

## Validation

### Automated Validation

Run the following commands to validate documentation changes:

```bash
# Lint documentation (includes link checking via mega-linter)
task dev-env:lint

# Expected: No linting errors and no broken links
```

### Manual Validation Checklist

- [ ] All links are valid and point to existing files
- [ ] Version information is current
- [ ] Command examples are tested and syntactically correct
- [ ] Prerequisites are clearly documented
- [ ] Validation steps include expected outcomes
- [ ] Agent-friendly workflows include decision trees
- [ ] Documentation follows established structure
- [ ] Content is accessible to target audience
- [ ] Cross-service dependencies are documented
- [ ] MCP integration patterns are included
- [ ] All code examples follow [Code Block Requirements](#code-block-requirements) with proper language identifiers
- [ ] No raw code appears outside of properly formatted code blocks
- [ ] MCP library references are valid against context7-libraries.json
- [ ] Context7 citations include library ID, version, and usage context

### Expected Outcomes

- Linting passes without errors
- No broken internal links detected
- All component directories have README.md files
- Documentation accurately reflects current state
- All decision trees are syntactically valid
- Cross-service dependencies are mapped
- YAML syntax is valid in all documentation code blocks

### MCP Integration Validation

Run the following commands to validate MCP library references and citations:

```bash
# Validate MCP library references against context7-libraries.json
for file in $(find . -name "*.md" -exec grep -l "context7-libraries.json\|get-library-docs\|resolve-library-id" {} \;); do
  echo "Validating MCP references in $file"
  # Extract library IDs from documentation
  grep -o '"[^"]*": "/[^"]*"' .kilocode/context7-libraries.json | sed 's/.*"//;s/".*//' | while read lib; do
    if grep -q "$lib" "$file"; then
      # Check if library exists in catalog
      jq -e "has(\"$lib\")" .kilocode/context7-libraries.json > /dev/null || echo "Referenced library $lib not in catalog (file: $file)"
    fi
  done
done

# Validate Context7 citation completeness
grep -r "Context7\|get-library-docs\|resolve-library-id" . --include="*.md" | while IFS=: read file line; do
  echo "Checking citation completeness in $file"
  # Check for library ID recording
  echo "$line" | grep -q "library.*id\|ID:" || echo "Missing library ID in citation: $file:$line"
  # Check for version information
  echo "$line" | grep -q "version\|v[0-9]" || echo "Missing version info in citation: $file:$line"
  # Check for usage context
  echo "$line" | grep -q "used for\|inform\|change" || echo "Missing usage context in citation: $file:$line"
done

# Expected: All library references valid, complete citations with ID, version, and context
```

## Machine-Readable Elements

### README Structure Schema

```yaml
# YAML Schema for README.md files
type: object
properties:
  title:
    type: string
    description: "Component title"
  overview:
    type: string
    description: "Brief component description"
  directory_layout:
    type: object
    description: "Directory structure with descriptions"
  prerequisites:
    type: array
    items:
      type: string
    description: "Required tools and conditions"
  operation:
    type: object
    properties:
      procedures:
        type: array
        items:
          type: string
      decision_trees:
        type: object
        description: "YAML decision trees for agentic workflows"
      monitoring_commands:
        type: object
        description: "Monitoring commands"
      cross_service_dependencies:
        type: object
        description: "Inter-service dependencies and health checks"
  troubleshooting:
    type: object
    properties:
      common_issues:
        type: array
        items:
          type: object
          properties:
            symptom:
              type: string
            diagnosis:
              type: string
            resolution:
              type: string
  maintenance:
    type: object
    properties:
      updates:
        type: string
      backups:
        type: string
      mcp_integration:
        type: object
        description: "Context7 library usage patterns"
  references:
    type: array
    items:
      type: string
required:
  - title
  - overview
  - prerequisites
  - operation
```

### Documentation Update Decision Tree

```yaml
# Decision tree for when to update documentation
start: "change_detected"
nodes:
  change_detected:
    question: "Has a repository change occurred?"
    yes: "affects_documentation"
    no: "end"
  affects_documentation:
    question: "Does the change affect documentation accuracy?"
    yes: "update_required"
    no: "end"
  update_required:
    question: "Is this a new component/feature?"
    yes: "create_new_docs"
    no: "update_existing_docs"
  create_new_docs:
    action: "Create new README.md using template"
    next: "validate_changes"
  update_existing_docs:
    action: "Update existing documentation"
    next: "validate_changes"
  validate_changes:
    action: "Run validation checks (lint, links, structure, decision trees)"
    next: "validation_passed"
  validation_passed:
    question: "Do validation checks pass?"
    yes: "commit_changes"
    no: "fix_issues"
  fix_issues:
    action: "Fix validation issues"
    next: "validate_changes"
  commit_changes:
    action: "Commit documentation changes"
    next: "end"
end: "end"
```

### Command Templates

```yaml
# Template for validation commands
validation_commands:
  lint: "task dev-env:lint"
  structure: "custom_readme_validator.sh" # If implemented
  decision_tree_validation: 'yq eval ''select(. == load("README.md"))'' README.md'
  link_integrity: "task dev-env:lint | grep -E '(broken|invalid)'"
  mcp_validation: "task documentation:validate-mcp"

# Template for documentation audit
audit_commands:
  find_missing_readmes: 'find cluster/apps -type d -depth 2 | xargs -I {} sh -c ''test -f {}/README.md || echo "Missing README: {}"'''
  check_versions: "grep -r 'version:' cluster/apps/ | head -10"
  validate_structure: 'for dir in cluster/apps/*/*/; do test -f "$dir/README.md" && echo "Checking $dir" || echo "Missing $dir"; done'

# Template for MCP integration validation
mcp_validation_commands:
  library_reference_check: 'grep -o ''"[^"]*": "/[^"]*"'' .kilocode/context7-libraries.json | sed ''s/.*"//;s/".*//'''
  citation_completeness_check: 'grep -r "Context7\|get-library-docs\|resolve-library-id" . --include="*.md"'
  catalog_validation: 'jq -e "has(\"<library_name>\")" .kilocode/context7-libraries.json'
```

### Cross-Service Dependency Template

```yaml
# Cross-service dependency mapping template
service_dependencies:
  <component_name>:
    depends_on:
      - <dependency1>
      - <dependency2>
    depended_by:
      - <dependent1>
      - <dependent2>
    critical_path: true/false
    health_check_command: "kubectl get <resource-type> -n <namespace> <name>"
```

### Enhanced Decision Tree Template

```yaml
# Enhanced decision tree template with validation commands
start: "component_health_check"
nodes:
  component_health_check:
    question: "Is <component> healthy?"
    command: "kubectl get <resource-type> -n <namespace> --no-headers | grep -v 'Ready\|Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "investigate_issue"
    no: "component_healthy"
  investigate_issue:
    action: "kubectl describe <resource-type> <name> -n <namespace>"
    log_command: "kubectl logs <pod-name> -n <namespace> --tail=50"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl top pods -n <namespace>"
    options:
      configuration_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  configuration_error:
    action: "Review values.yaml and Helm configuration"
    commands:
      - "helm get values <release> -n <namespace>"
      - "kubectl get cm <configmap> -n <namespace> -o yaml"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    commands:
      - "kubectl get pods -n <dependency-namespace>"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    commands:
      - "kubectl top nodes"
      - "kubectl describe nodes | grep -A 10 'Capacity'"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    validation_commands:
      - "kubectl apply -f <fixed-config>"
      - "kubectl rollout restart deployment/<deployment> -n <namespace>"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get <resource-type> -n <namespace> --no-headers | grep 'Ready\|Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "component_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  component_healthy:
    action: "Component verified healthy"
    next: "end"
end: "end"
```

### Standardized Decision Tree Template

```yaml
# Standard decision tree template for all components
start: "component_health_check"
nodes:
  component_health_check:
    question: "Is <component> healthy?"
    command: "kubectl get <resource-type> -n <namespace> --no-headers | grep -v 'Ready\|Running'"
    yes: "investigate_issue"
    no: "component_healthy"
  investigate_issue:
    action: "kubectl describe <resource-type> <name> -n <namespace>"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      configuration_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  configuration_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get <resource-type> -n <namespace> --no-headers | grep 'Ready\|Running'"
    yes: "component_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  component_healthy:
    action: "Component verified healthy"
    next: "end"
end: "end"
```

## Enforcement

- **Mandatory Linting**: All documentation changes must be validated by running `task dev-env:lint` immediately after modifications and before any commits.
- Documentation changes must pass mega-linter checks
- Pull requests modifying documentation require review for compliance with these standards
- App components (under `cluster/apps/`) must have README.md files; new apps require documentation before merge
- All decision trees must pass YAML syntax validation
- Cross-service dependencies must be documented and validated
- **Code Block Compliance**: All code examples, configurations, and command examples must follow the [Code Block Requirements](#code-block-requirements) for proper formatting and language identification. Reviewers must check for and correct improper code block usage.

## Related Rules

- [core_rules.md](core_rules.md) — kubectl workflow guidelines
- [procedures.md](procedures.md) — common operational patterns and Context7 library usage policy
- [renovate.md](renovate.md) — Renovate configuration management standards
