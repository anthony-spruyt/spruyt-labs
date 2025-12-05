# authentik - Identity Provider

## Overview

authentik is an open-source Identity Provider that unifies identity management across applications and services. It provides authentication, authorization, and user management capabilities for the spruyt-labs homelab infrastructure.

## Directory Layout

```yaml
authentik/
├── app/
│   ├── authentik-cnpg-cluster.yaml      # PostgreSQL cluster configuration
│   ├── authentik-cnpg-object-stores.yaml # Object storage configuration
│   ├── authentik-cnpg-poolers.yaml      # Connection poolers
│   ├── authentik-cnpg-scheduled-backups.yaml # Backup configuration
│   ├── kustomization.yaml               # Kustomize configuration
│   ├── kustomizeconfig.yaml             # Kustomize config
│   ├── persistent-volume-claim.yaml      # Persistent volume claims
│   ├── release.yaml                      # Helm release configuration
│   └── values.yaml                       # Helm values
├── ks.yaml                               # Kustomization configuration
└── README.md                             # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- PostgreSQL operator (CNPG) deployed
- Storage class configured for persistent volumes
- Ingress controller configured
- TLS certificates available

### Prerequisites Validation

```bash
# Check authentik pods are running
kubectl get pods -n authentik-system

# Verify service is available
kubectl get svc -n authentik-system

# Check ingress route
kubectl get ingressroute -n authentik-system

# Verify TLS certificate
kubectl get certificates -n authentik-system
```

## Operation

### Procedures

1. **User management**:

   - Access authentik admin interface at `https://authentik.${EXTERNAL_DOMAIN}`
   - Create users, groups, and applications

2. **Backup verification**:

```bash
kubectl get scheduledbackups -n authentik-system
```

3. **Connection pooler monitoring**:

   ```bash
   kubectl get poolers -n authentik-system
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate user management
kubectl get pods -n authentik-system --no-headers | grep 'Running'

# Expected: Authentik pods running

# Validate backup verification
kubectl get scheduledbackups -n authentik-system

# Expected: Scheduled backups listed

# Validate connection pooler monitoring
kubectl get poolers -n authentik-system

# Expected: Connection poolers listed
```

### Decision Trees

```yaml
# authentik operational decision tree
start: "authentik_health_check"
nodes:
  authentik_health_check:
    question: "Is authentik healthy?"
    command: "kubectl get pods -n authentik-system --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "authentik_healthy"
  investigate_issue:
    action: "kubectl describe pods -n authentik-system | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      database_issue: "PostgreSQL connection problem"
      config_error: "Configuration mismatch"
      resource_constraint: "Resource limitation"
      network_issue: "Network connectivity"
  database_issue:
    action: "Check CNPG cluster: kubectl get clusters -n authentik-system"
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
    command: "kubectl get pods -n authentik-system --no-headers | grep 'Running'"
    yes: "authentik_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  authentik_healthy:
    action: "authentik verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# authentik cross-service dependencies
service_dependencies:
  authentik:
    depends_on:
      - cnpg-system/cnpg-operator
      - traefik/traefik
      - cert-manager/cert-manager
    depended_by:
      - Various applications requiring authentication
    critical_path: true
    health_check_command: "kubectl get pods -n authentik-system --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **Database connection failures**:

   - **Symptom**: Pods stuck in CrashLoopBackOff
   - **Diagnosis**: Check CNPG cluster health and connection details
   - **Resolution**: Verify PostgreSQL credentials and network connectivity

2. **TLS certificate issues**:

   - **Symptom**: Ingress route shows certificate errors
   - **Diagnosis**: Check cert-manager certificate status
   - **Resolution**: Verify certificate DNS names and issuer configuration

3. **Resource constraints**:
   - **Symptom**: Pods in Pending state
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

## Maintenance

### Updates

```bash
# Update authentik Helm chart
helm repo update
helm upgrade authentik authentik/authentik -n authentik-system -f values.yaml
```

### Backups

```bash
# Verify scheduled backups
kubectl get scheduledbackups -n authentik-system

# Check backup status
kubectl get backups -n authentik-system
```

### MCP Integration

- **Library ID**: `authentik`
- **Version**: `2024.10.3`
- **Usage**: Authentication and authorization management
- **Citation**: Use `resolve-library-id` for authentik documentation and API references

## References

- [authentik Documentation](https://goauthentik.io/docs/)
- [CNPG Operator Documentation](https://cloudnative-pg.io/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
