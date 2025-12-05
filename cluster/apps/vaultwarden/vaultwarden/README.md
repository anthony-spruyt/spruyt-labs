# vaultwarden - Password Manager

## Overview

Vaultwarden is an unofficial Bitwarden-compatible server implementation that provides secure password management for the spruyt-labs homelab infrastructure. It offers a self-hosted solution for storing and managing sensitive credentials with end-to-end encryption.

## Directory Layout

```yaml
vaultwarden/
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
- Persistent storage configured for data persistence
- TLS certificates available for secure connections
- SMTP server configured for email notifications
- Rook Ceph storage provisioned (dependency)

## Operation

### Procedures

1. **Password manager management**:

   - Access vaultwarden web interface
   - Monitor user authentication and data storage
   - Manage backup and restore procedures

2. **Persistent volume monitoring**:

   ```bash
   # Check persistent volume claims
   kubectl get pvc -n vaultwarden

   # Verify volume binding
   kubectl get pv | grep vaultwarden
   ```

3. **Certificate renewal monitoring**:

   ```bash
   # Check certificate expiration
   kubectl get certificates -n vaultwarden -o wide

   # Check certificate events
   kubectl get events -n vaultwarden | grep certificate
   ```

### Decision Trees

```yaml
# vaultwarden operational decision tree
start: "vaultwarden_health_check"
nodes:
  vaultwarden_health_check:
    question: "Is vaultwarden healthy?"
    command: "kubectl get pods -n vaultwarden --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "vaultwarden_healthy"
  investigate_issue:
    action: "kubectl describe pods -n vaultwarden | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      storage_issue: "Persistent volume problem"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
      tls_issue: "TLS certificate problem"
  storage_issue:
    action: "Check PVC and PV: kubectl get pvc -n vaultwarden"
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
  tls_issue:
    action: "Check certificate status: kubectl get certificates -n vaultwarden"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n vaultwarden --no-headers | grep 'Running'"
    yes: "vaultwarden_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  vaultwarden_healthy:
    action: "vaultwarden verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# vaultwarden cross-service dependencies
service_dependencies:
  vaultwarden:
    depends_on:
      - rook-ceph/rook-ceph-cluster
      - traefik/traefik
      - cert-manager/cert-manager
    depended_by:
      - Users requiring password management
      - Authentication systems
      - Security workflows
    critical_path: true
    health_check_command: "kubectl get pods -n vaultwarden --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Persistent volume binding failures**:

   - **Symptom**: Pods stuck in Pending state
   - **Diagnosis**: Check PVC status and storage class availability
   - **Resolution**: Verify Rook Ceph storage provisioning and PVC configuration

2. **TLS certificate issues**:

   - **Symptom**: Web interface connection failures
   - **Diagnosis**: Check cert-manager certificate status and TLS configuration
   - **Resolution**: Verify certificate DNS names and issuer configuration

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Network connectivity issues**:

   - **Symptom**: Web interface inaccessible
   - **Diagnosis**: Check network policies and ingress configuration
   - **Resolution**: Verify network connectivity and firewall rules

## Maintenance

### Updates

```bash
# Update vaultwarden using Flux
flux reconcile kustomization vaultwarden --with-source
```

### Backups

```bash
# Verify persistent volume backups
kubectl get pvc -n vaultwarden

# Check backup status if using Velero
kubectl get backups -n vaultwarden
```

### MCP Integration

- **Library ID**: `vaultwarden-password-management`
- **Version**: `v1.29.0`
- **Usage**: Secure password storage and management
- **Citation**: Use `resolve-library-id` for vaultwarden configuration and API references

## References

- [Vaultwarden Documentation](https://github.com/dani-garcia/vaultwarden)
- [Bitwarden API Documentation](https://bitwarden.com/help/api/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of vaultwarden tasks.

### vaultwarden Health Check Workflow

```yaml
# vaultwarden health check decision tree
start: "check_vaultwarden_pods"
nodes:
  check_vaultwarden_pods:
    question: "Are vaultwarden pods running?"
    command: "kubectl get pods -n vaultwarden --no-headers | grep -v 'Running' | wc -l"
    validation: "grep -q '^0$'"
    yes: "check_web_interface"
    no: "restart_vaultwarden_pods"
  check_web_interface:
    question: "Is vaultwarden web interface accessible?"
    command: "kubectl exec -n vaultwarden deployment/vaultwarden -- curl -s -I http://localhost:80 | grep -c 'HTTP/1.1 200'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "WEB_FAIL"}'' | grep -q ''OK'''
    yes: "check_database"
    no: "fix_web_interface"
  check_database:
    question: "Is database connectivity working?"
    command: "kubectl logs -n vaultwarden -l app.kubernetes.io/name=vaultwarden --tail=20 | grep -c 'Database.*migrated\\|Starting.*migrations'"
    validation: 'awk ''{if ($1 >= 1) print "OK"; else print "DB_FAIL"}'' | grep -q ''OK'''
    yes: "vaultwarden_healthy"
    no: "fix_database_connection"
  restart_vaultwarden_pods:
    action: "Restart vaultwarden pods"
    next: "check_vaultwarden_pods"
  fix_web_interface:
    action: "Check vaultwarden web server configuration"
    next: "check_web_interface"
  fix_database_connection:
    action: "Check database configuration and connectivity"
    next: "check_database"
  vaultwarden_healthy:
    action: "Vaultwarden password manager is healthy"
    next: "end"
end: "end"
```

### Enhanced MCP Integration with Context7 Library Usage Guidelines

### Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) to identify existing entries for vaultwarden documentation.
- Confirm the catalog entry contains the documentation or API details needed for vaultwarden operations.
- Note the library identifier, source description, and version information that appears in the catalog.

### When the catalog covers vaultwarden documentation needs

1. Use the information from [`context7-libraries.json`](../../../../.kilocode/context7-libraries.json) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant snippets in change notes or pull request descriptions.
3. Mention how the retrieved material informed vaultwarden configuration changes.

### When vaultwarden documentation is missing or outdated

1. Run `resolve-library-id` with a precise description of the needed documentation.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in the root README.md and describe the gap.
3. Once a new library is added, update worklogs with the new ID and any prerequisites uncovered during the search.

### Documenting Citations and MCP Usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in vaultwarden change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions made when interpreting vaultwarden documentation.
