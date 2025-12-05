# [Component Name] - [Brief Description]

## Purpose and Scope

[One to two sentences describing the service and primary objective of the runbook.]

Objectives:

- [List key objectives]

## Overview

[Provide a brief description of the component, its purpose, and its role in the spruyt-labs homelab infrastructure.]

## Directory Layout

```yaml
[component-name]/
├── app/
│   ├── [configuration-files.yaml]  # [Description of configuration files]
│   ├── kustomization.yaml          # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- [List required tools and conditions]
- [List any dependencies or prerequisites]
- [Specify environmental conditions]

### Validation

```bash
# [Validation command description]
[validation command]

# [Additional validation command]
[additional validation command]
```

## Operation

### Procedures

1. **[Procedure 1 Description]**:

   - [Procedure details]

   ```bash
   [Procedure command]
   ```

2. **[Procedure 2 Description]**:
   ```bash
   [Procedure command]
   ```

### Decision Trees

```yaml
# [Component] operational decision tree
start: "[component]_health_check"
nodes:
  [component]_health_check:
    question: "Is [component] healthy?"
    command: "kubectl get pods -n [namespace] --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "[component]_healthy"
  investigate_issue:
    action: "kubectl describe pods -n [namespace] | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      configuration_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  configuration_error:
    action: "Review values.yaml and Helm configuration"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    next: "apply_fix"
  network_issue:
    action: "Investigate network policies and connectivity"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n [namespace] --no-headers | grep 'Running'"
    yes: "[component]_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  [component]_healthy:
    action: "[Component] verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# [Component] cross-service dependencies
service_dependencies:
  [component_name]:
    depends_on:
      - <dependency1>
      - <dependency2>
    depended_by:
      - <dependent1>
      - <dependent2>
    critical_path: true/false
    health_check_command: "kubectl get <resource-type> -n [namespace] <name>"
```

## Troubleshooting

### Common Issues

1. **[Issue 1 Description]**:

   - **Symptom**: [Symptom description]
   - **Diagnosis**: [Diagnosis procedure]
   - **Resolution**: [Resolution steps]

2. **[Issue 2 Description]**:
   - **Symptom**: [Symptom description]
   - **Diagnosis**: [Diagnosis procedure]
   - **Resolution**: [Resolution steps]

## Maintenance

### Updates

```bash
# [Update procedure description]
[update command]
```

### Backups

```bash
# [Backup procedure description]
[backup command]
```

### MCP Integration

- **Library ID**: `[library-id]`
- **Version**: `[version]`
- **Usage**: [Brief description of usage]
- **Citation**: Use `resolve-library-id` for [component] documentation and API references

## References

- [Reference 1 Title](https://reference1-url.com)
- [Reference 2 Title](https://reference2-url.com)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of [component] tasks.

### [Component] Health Check Workflow

```bash
If [health check command] > /dev/null
Then:
  Run [diagnostic command]
  Expected output: [expected result]
  If [condition]:
    Run [recovery command]
    Expected output: [expected result]
    Recovery: [recovery action]
  Else:
    Proceed to [next check]
Else:
  Proceed to [next check]
```

## Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for [component] documentation.
- Confirm the catalog entry contains the documentation or API details needed for [component] operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers [component] documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed [component] configuration changes.

### When [component] documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in [component] change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting [component] documentation.
