# authentik - Identity Provider

## Overview

authentik is an open-source Identity Provider that unifies identity management across applications and services. It provides authentication, authorization, and user management capabilities for the spruyt-labs homelab infrastructure.

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

   - Access authentik admin interface at `https://auth.${EXTERNAL_DOMAIN}`
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

## References

- [authentik Documentation](https://goauthentik.io/docs/)
- [CNPG Operator Documentation](https://cloudnative-pg.io/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
