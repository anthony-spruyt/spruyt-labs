# plugin-barman-cloud - Barman Cloud Plugin

## Overview

Barman Cloud Plugin provides cloud storage integration for PostgreSQL backups managed by CloudNativePG. It enables backup and restore operations with cloud storage providers for enhanced data protection and disaster recovery capabilities.

## Directory Layout

```yaml
plugin-barman-cloud/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- CloudNativePG operator deployed and operational
- Cloud storage credentials configured (AWS S3, Azure Blob, Google Cloud Storage)
- Proper network connectivity to cloud storage providers

## Operation

### Procedures

1. **Cloud backup management**:

```bash
# Check backup status
kubectl get backups -A

# Verify cloud storage connectivity
kubectl logs -n cnpg-system <plugin-pod-name> | grep "cloud storage"
```

2. **Backup configuration**:

```bash
# Check backup configuration
kubectl get scheduledbackups -A

# Verify backup retention policies
kubectl get backupconfigurations -A
```

3. **Performance monitoring**:

```bash
# Check plugin resource usage
kubectl top pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud

# Monitor backup operations
kubectl logs -n cnpg-system <plugin-pod-name> | grep "backup"
```

### Decision Trees

```yaml
# Barman Cloud Plugin operational decision tree
start: "barman_cloud_health_check"
nodes:
  barman_cloud_health_check:
    question: "Is Barman Cloud Plugin healthy?"
    command: "kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "barman_cloud_healthy"
  investigate_issue:
    action: "kubectl describe pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      cloud_connectivity: "Cloud storage connectivity problem"
      credential_issue: "Credential configuration issue"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  cloud_connectivity:
    action: "Check cloud storage connectivity: kubectl logs -n cnpg-system <plugin-pod-name> | grep 'cloud'"
    next: "apply_fix"
  credential_issue:
    action: "Verify cloud credentials: kubectl get secrets -n cnpg-system"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  network_issue:
    action: "Investigate network policies and connectivity"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud --no-headers | grep 'Running'"
    yes: "barman_cloud_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  barman_cloud_healthy:
    action: "Barman Cloud Plugin verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Barman Cloud Plugin cross-service dependencies
service_dependencies:
  plugin-barman-cloud:
    depends_on:
      - cnpg-system/cnpg-operator
      - external-secrets/external-secrets
    depended_by:
      - All PostgreSQL clusters requiring cloud backups
      - All applications using managed PostgreSQL databases
    critical_path: true
    health_check_command: "kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Cloud storage connectivity failures**:

   - **Symptom**: Backup operations failing
   - **Diagnosis**: Check cloud storage connectivity and credentials
   - **Resolution**: Verify cloud storage configuration and network connectivity

2. **Credential configuration errors**:

   - **Symptom**: Authentication failures in logs
   - **Diagnosis**: Check cloud storage credentials and access permissions
   - **Resolution**: Verify cloud storage credentials and access policies

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Network connectivity issues**:

   - **Symptom**: Backup operations timing out
   - **Diagnosis**: Check network policies and cloud storage connectivity
   - **Resolution**: Verify network configuration and firewall rules

## Maintenance

### Updates

```bash
# Update Barman Cloud Plugin using Flux
flux reconcile kustomization plugin-barman-cloud --with-source
```

### Backup Management

```bash
# Verify scheduled backups
kubectl get scheduledbackups -A

# Check backup status
kubectl get backups -A
```

### MCP Integration

- **Library ID**: `barman-cloud-backup-plugin`
- **Version**: `v1.22.0`
- **Usage**: Cloud storage integration for PostgreSQL backups
- **Citation**: Use `resolve-library-id` for Barman Cloud configuration and troubleshooting

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Flux CD Documentation](https://fluxcd.io/flux/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of Barman Cloud Plugin tasks.

### Barman Cloud Plugin Health Check Workflow

```yaml
# Barman Cloud Plugin health check decision tree
start: "check_barman_cloud_pods"
nodes:
  check_barman_cloud_pods:
    question: "Are Barman Cloud Plugin pods running?"
    command: "kubectl get pods -n cnpg-system -l app.kubernetes.io/name=barman-cloud --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_cloud_storage_connectivity"
    no: "restart_barman_cloud_pods"
  check_cloud_storage_connectivity:
    question: "Is cloud storage connectivity working?"
    command: "kubectl logs -n cnpg-system -l app.kubernetes.io/name=barman-cloud --tail=20 | grep -c 'cloud.*success\\|storage.*connected'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "CONNECT_FAIL"}'' | grep -q ''OK'''
    yes: "check_backup_operations"
    no: "fix_cloud_credentials"
  check_backup_operations:
    question: "Are backup operations working?"
    command: "kubectl get backups -A --no-headers | wc -l"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "NO_BACKUPS"}'' | grep -q ''OK'''
    yes: "barman_cloud_healthy"
    no: "fix_backup_config"
  restart_barman_cloud_pods:
    action: "Restart Barman Cloud Plugin pods"
    next: "check_barman_cloud_pods"
  fix_cloud_credentials:
    action: "Check and fix cloud storage credentials"
    next: "check_cloud_storage_connectivity"
  fix_backup_config:
    action: "Check backup configuration and scheduled backups"
    next: "check_backup_operations"
  barman_cloud_healthy:
    action: "Barman Cloud Plugin for PostgreSQL backups is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for Barman Cloud Plugin documentation.
- Confirm the catalog entry contains the documentation or API details needed for Barman Cloud Plugin operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers Barman Cloud Plugin documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed Barman Cloud Plugin configuration changes.

### When Barman Cloud Plugin documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in Barman Cloud Plugin change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting Barman Cloud Plugin documentation.
