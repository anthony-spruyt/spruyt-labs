# n8n - Workflow Automation

## Overview

n8n is a workflow automation tool that connects various applications and services through visual workflows. It provides a low-code platform for integrating APIs, databases, and cloud services in the spruyt-labs homelab infrastructure, enabling powerful automation capabilities.

## Directory Layout

```yaml
n8n/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── n8n-cnpg-poolers.yaml       # Connection poolers
│   ├── n8n-cnpg-scheduled-backups.yaml # Backup configuration
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- PostgreSQL operator (CNPG) deployed
- Storage class configured for persistent volumes
- Ingress controller configured
- TLS certificates available
- Rook Ceph storage provisioned (dependency)

## Operation

### Procedures

1. **Workflow management**:

   - Access n8n web interface at `https://n8n.${EXTERNAL_DOMAIN}`
   - Create and manage workflows
   - Monitor workflow execution

2. **Database monitoring**:

   ```bash
   # Check connection pooler status
   kubectl get poolers -n n8n-system

   # Verify scheduled backups
   kubectl get scheduledbackups -n n8n-system
   ```

3. **Performance monitoring**:

   ```bash
   # Check n8n service status
   kubectl get pods -n n8n-system

   # Monitor resource usage
   kubectl top pods -n n8n-system
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate workflow management
kubectl get pods -n n8n-system --no-headers | grep 'Running'

# Expected: n8n pods running

# Validate database monitoring
kubectl get poolers -n n8n-system

# Expected: Connection poolers listed

# Validate performance monitoring
kubectl top pods -n n8n-system

# Expected: Resource usage displayed
```

### Decision Trees

```yaml
# n8n operational decision tree
start: "n8n_health_check"
nodes:
  n8n_health_check:
    question: "Is n8n healthy?"
    command: "kubectl get pods -n n8n-system --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "n8n_healthy"
  investigate_issue:
    action: "kubectl describe pods -n n8n-system | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      database_issue: "PostgreSQL connection problem"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  database_issue:
    action: "Check CNPG cluster: kubectl get clusters -n n8n-system"
    next: "apply_fix"
  config_error:
    action: "Review values.yaml and Helm configuration"
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
    command: "kubectl get pods -n n8n-system --no-headers | grep 'Running'"
    yes: "n8n_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  n8n_healthy:
    action: "n8n verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# n8n cross-service dependencies
service_dependencies:
  n8n:
    depends_on:
      - cnpg-system/cnpg-operator
      - traefik/traefik
      - cert-manager/cert-manager
      - rook-ceph/rook-ceph-cluster
    depended_by:
      - Automation workflows
      - Integration services
      - Data processing pipelines
    critical_path: true
    health_check_command: "kubectl get pods -n n8n-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Database connection failures**:

   - **Symptom**: Pods stuck in CrashLoopBackOff
   - **Diagnosis**: Check CNPG cluster health and connection details
   - **Resolution**: Verify PostgreSQL credentials and network connectivity

2. **Workflow execution errors**:

   - **Symptom**: Workflows failing to execute
   - **Diagnosis**: Check n8n logs and workflow configuration
   - **Resolution**: Verify workflow syntax and API connections

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Network connectivity issues**:

   - **Symptom**: External API connections failing
   - **Diagnosis**: Check network policies and egress connectivity
   - **Resolution**: Verify network configuration and firewall rules

## Maintenance

### Updates

```bash
# Update n8n using Flux
flux reconcile kustomization n8n --with-source
```

### Backup Management

```bash
# Verify scheduled backups
kubectl get scheduledbackups -n n8n-system

# Check backup status
kubectl get backups -n n8n-system
```

### MCP Integration

- **Library ID**: `n8n-workflow-automation`
- **Version**: `v1.30.0`
- **Usage**: Workflow automation and API integration
- **Citation**: Use `resolve-library-id` for n8n configuration and API references

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n API Documentation](https://docs.n8n.io/api/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of n8n tasks.

### n8n Health Check Workflow

```yaml
# n8n health check decision tree
start: "check_n8n_pods"
nodes:
  check_n8n_pods:
    question: "Are n8n pods running?"
    command: "kubectl get pods -n n8n-system --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_n8n_web_interface"
    no: "restart_n8n_pods"
  check_n8n_web_interface:
    question: "Is n8n web interface accessible?"
    command: "kubectl exec -n n8n-system deployment/n8n -- curl -s -I http://localhost:5678 | grep -c 'HTTP/1.1 200'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "WEB_FAIL"}'' | grep -q ''OK'''
    yes: "check_database_connectivity"
    no: "fix_web_interface"
  check_database_connectivity:
    question: "Is database connectivity working?"
    command: "kubectl logs -n n8n-system -l app.kubernetes.io/name=n8n --tail=20 | grep -c 'Database.*connected\\|PostgreSQL.*ready'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "DB_FAIL"}'' | grep -q ''OK'''
    yes: "n8n_healthy"
    no: "fix_database_connection"
  restart_n8n_pods:
    action: "Restart n8n pods"
    next: "check_n8n_pods"
  fix_web_interface:
    action: "Check n8n web server configuration and ports"
    next: "check_n8n_web_interface"
  fix_database_connection:
    action: "Check PostgreSQL connection and credentials"
    next: "check_database_connectivity"
  n8n_healthy:
    action: "n8n workflow automation tool is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for n8n documentation.
- Confirm the catalog entry contains the documentation or API details needed for n8n operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers n8n documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed n8n configuration changes.

### When n8n documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in n8n change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting n8n documentation.
