# flux-operator - Flux Operator

## Overview

Flux Operator is a Kubernetes operator that manages Flux deployments using custom resources. It provides a declarative way to manage Flux instances and their components, enabling GitOps workflows for continuous delivery in the spruyt-labs homelab infrastructure.

## Directory Layout

```yaml
flux-operator/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with proper RBAC configured
- Git repository accessible from cluster
- SSH keys or credentials for Git access
- Proper network connectivity to Git repository
- Flux instance already deployed

## Operation

### Procedures

1. **Flux operator management**:

```bash
# Check flux-operator service status
kubectl get pods -n flux-system

# Verify operator reconciliation
kubectl logs -n flux-system <operator-pod-name> | grep "reconciliation"

# Check operator events
kubectl get events -n flux-system | grep flux-operator
```

2. **Configuration management**:

```bash
# Check current configuration
kubectl get configmap -n flux-system

# Verify operator configuration
kubectl get fluxoperators -A -o yaml
```

3. **Performance monitoring**:

   ```bash
   # Check operator reconciliation status
   kubectl logs -n flux-system <operator-pod-name> | grep "reconciliation"

   # Monitor operator performance
   kubectl top pods -n flux-system
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate flux-operator management
kubectl get pods -n flux-system --no-headers | grep 'Running'

# Expected: Flux operator pods running

# Validate configuration management
kubectl get configmap -n flux-system

# Expected: Configuration maps listed

# Validate performance monitoring
kubectl top pods -n flux-system

# Expected: Resource usage displayed
```

### Decision Trees

```yaml
# flux-operator operational decision tree
start: "flux_operator_health_check"
nodes:
  flux_operator_health_check:
    question: "Is flux-operator healthy?"
    command: "kubectl get pods -n flux-system --no-headers | grep -v 'Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "investigate_issue"
    no: "flux_operator_healthy"
  investigate_issue:
    action: "kubectl describe pods -n flux-system"
    log_command: "kubectl logs -n flux-system <operator-pod-name> --tail=50"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n flux-system --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl top pods -n flux-system"
    options:
      config_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  config_error:
    action: "Review values.yaml and Helm configuration"
    commands:
      - "helm get values flux-operator -n flux-system"
      - "kubectl get cm -n flux-system -o yaml"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    commands:
      - "kubectl get pods -n flux-system"
      - "kubectl get clusterroles,clusterrolebindings | grep flux"
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
      - "kubectl rollout restart deployment/<deployment> -n flux-system"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n flux-system --no-headers | grep 'Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "flux_operator_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  flux_operator_healthy:
    action: "flux-operator verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# flux-operator cross-service dependencies
service_dependencies:
  flux-operator:
    depends_on:
      - flux-system/flux-instance
      - cert-manager/cert-manager
    depended_by:
      - All Flux-managed workloads
      - All GitOps operations
      - All infrastructure components
    critical_path: true
    health_check_command: "kubectl get pods -n flux-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Git repository connectivity failures**:

   - **Symptom**: Operator unable to access Git repository
   - **Diagnosis**: Check Git repository connectivity and credentials
   - **Resolution**: Verify SSH keys and repository URLs

2. **RBAC permission errors**:

   - **Symptom**: Access denied errors in logs
   - **Diagnosis**: Check RBAC permissions and service accounts
   - **Resolution**: Verify cluster roles and role bindings

3. **Reconciliation delays**:

   - **Symptom**: Slow operator reconciliation
   - **Diagnosis**: Check operator performance and resource usage
   - **Resolution**: Verify operator resources and network latency

4. **Configuration errors**:

   - **Symptom**: Operator service not starting
   - **Diagnosis**: Check configuration syntax and operator parameters
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update flux-operator using Flux
flux reconcile kustomization flux-operator --with-source
```

### Configuration Management

```bash
# Update flux-operator configuration
flux reconcile kustomization flux-operator --with-source

# Verify configuration changes
kubectl logs -n flux-system <operator-pod-name> | grep "configuration"
```

### MCP Integration

- **Library ID**: `flux-operator-gitops-management`
- **Version**: `v1.2.0`
- **Usage**: Flux operator management and GitOps operations
- **Citation**: Use `resolve-library-id` for flux-operator configuration and API references

## References

- [Flux Operator Documentation](https://fluxcd.io/flux/)
- [Flux GitOps Toolkit](https://fluxcd.io/flux/guides/)
- [Kubernetes Operator Framework](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Flux Helm Chart](https://github.com/fluxcd/flux2)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of flux-operator tasks.

### flux-operator Health Check Workflow

```yaml
# flux-operator health check decision tree
start: "check_flux_operator_pods"
nodes:
  check_flux_operator_pods:
    question: "Are flux-operator pods running?"
    command: "kubectl get pods -n flux-system -l app.kubernetes.io/name=flux-operator --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_operator_reconciliation"
    no: "restart_operator_pods"
  check_operator_reconciliation:
    question: "Is operator reconciliation working?"
    command: "kubectl logs -n flux-system -l app.kubernetes.io/name=flux-operator --tail=100 | grep -i 'error\\|failed' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_managed_flux_instances"
    no: "investigate_reconciliation_errors"
  check_managed_flux_instances:
    question: "Are managed Flux instances healthy?"
    command: "kubectl get fluxinstances -A --no-headers | awk '{print $2}' | grep -v 'Ready' | wc -l"
    validation: "grep -q '^0$'"
    yes: "flux_operator_healthy"
    no: "fix_flux_instances"
  restart_operator_pods:
    action: "Restart flux-operator pods"
    next: "check_flux_operator_pods"
  investigate_reconciliation_errors:
    action: "Check operator logs for reconciliation errors"
    next: "check_operator_reconciliation"
  fix_flux_instances:
    action: "Fix managed Flux instance issues"
    next: "check_managed_flux_instances"
  flux_operator_healthy:
    action: "flux-operator and managed instances are healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for flux-operator documentation.
- Confirm the catalog entry contains the documentation or API details needed for flux-operator operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers flux-operator documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed flux-operator configuration changes.

### When flux-operator documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in flux-operator change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting flux-operator documentation.
