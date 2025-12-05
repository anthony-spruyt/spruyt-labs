# CloudNativePG Operator - PostgreSQL Management

## Overview

CloudNativePG Operator provides comprehensive PostgreSQL management for Kubernetes, offering high availability, backup, restore, and monitoring capabilities. It serves as the primary PostgreSQL operator for the spruyt-labs cluster, managing database instances for various applications.

## Directory Layout

```yaml
cnpg-operator/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── plugin-barman-cloud/             # Barman cloud plugin
│   ├── app/
│   │   ├── kustomization.yaml      # Plugin kustomization
│   │   ├── kustomizeconfig.yaml    # Plugin config
│   │   ├── release.yaml            # Plugin release
│   │   └── values.yaml             # Plugin values
│   └── ks.yaml                     # Plugin kustomization
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Storage class configured for persistent volumes
- Network connectivity between nodes
- Proper RBAC permissions

## Operation

### Procedures

1. **PostgreSQL cluster management**:

```bash
# Create PostgreSQL cluster
kubectl apply -f postgresql-cluster.yaml

# Check cluster status
kubectl get clusters -n <namespace>
```

2. **Backup management**:

```bash
# Check scheduled backups
kubectl get scheduledbackups -A

# Check backup status
kubectl get backups -A
```

3. **Monitoring and maintenance**:

```bash
# Check cluster health
kubectl get clusters -A -o wide

# Check pod status
kubectl get pods -A -l cluster-name=<cluster-name>
```

### Decision Trees

```yaml
# CNPG operator decision tree
start: "cnpg_health_check"
nodes:
  cnpg_health_check:
    question: "Is CNPG operator healthy?"
    command: "kubectl get pods -n cnpg-system --no-headers | grep -v 'Running'"
    validation: "wc -l | grep -q '^0$'"
    yes: "investigate_issue"
    no: "cnpg_healthy"
  investigate_issue:
    action: "kubectl describe pods -n cnpg-system"
    log_command: "kubectl logs -n cnpg-system <operator-pod-name> --tail=50"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    diagnostic_commands:
      - "kubectl get events -n cnpg-system --sort-by=.metadata.creationTimestamp | tail -10"
      - "kubectl top pods -n cnpg-system"
    options:
      config_error: "Configuration issue"
      dependency_failure: "Dependency problem"
      resource_constraint: "Resource limitation"
  config_error:
    action: "Review values.yaml and Helm configuration"
    commands:
      - "helm get values cnpg-operator -n cnpg-system"
      - "kubectl get crds | grep postgresql"
    next: "apply_fix"
  dependency_failure:
    action: "Check cross-service dependencies"
    commands:
      - "kubectl get pvc -n <namespace>"
      - "kubectl get pods -n rook-ceph"
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
      - "kubectl rollout restart deployment/<deployment> -n cnpg-system"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n cnpg-system --no-headers | grep 'Running'"
    validation: "wc -l | grep -q '^[1-9]'"
    yes: "cnpg_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  cnpg_healthy:
    action: "CNPG operator verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# CNPG cross-service dependencies
service_dependencies:
  cnpg-operator:
    depends_on:
      - rook-ceph/rook-ceph
      - cert-manager/cert-manager
    depended_by:
      - authentik-system/authentik
      - All applications requiring PostgreSQL
      - All workloads using managed databases
    critical_path: true
    health_check_command: "kubectl get pods -n cnpg-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **PostgreSQL cluster creation failures**:

   - **Symptom**: Clusters stuck in initializing state
   - **Diagnosis**: Check storage provisioning and network connectivity
   - **Resolution**: Verify storage class and network policies

2. **Backup configuration errors**:

   - **Symptom**: Scheduled backups not running
   - **Diagnosis**: Check backup configuration and storage access
   - **Resolution**: Verify backup storage credentials and schedules

3. **Operator reconciliation loops**:
   - **Symptom**: Operator pods restarting frequently
   - **Diagnosis**: Check operator logs and resource constraints
   - **Resolution**: Adjust resource limits and check for configuration errors

## Maintenance

### Updates

```bash
# Update CNPG operator
helm repo update
helm upgrade cnpg-operator cloudnative-pg/cloudnative-pg -n cnpg-system -f values.yaml
```

### Database Management

```bash
# Check PostgreSQL cluster status
kubectl get clusters -A

# Check backup status
kubectl get backups -A
```

### MCP Integration

- **Library ID**: `cloudnative-pg-operator`
- **Version**: `v1.22.0`
- **Usage**: PostgreSQL cluster management and automation
- **Citation**: Use `resolve-library-id` for CNPG configuration and troubleshooting

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for CNPG operator documentation.
- Confirm the catalog entry contains the documentation or API details needed for CNPG operator operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers CNPG operator documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed CNPG operator configuration changes.

### When CNPG operator documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in CNPG operator change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting CNPG operator documentation.

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [CNPG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
