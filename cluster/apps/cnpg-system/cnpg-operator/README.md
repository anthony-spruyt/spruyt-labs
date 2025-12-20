# CloudNativePG Operator - PostgreSQL Management

## Overview

CloudNativePG Operator provides comprehensive PostgreSQL management for Kubernetes, offering high availability, backup, restore, and monitoring capabilities. It serves as the primary PostgreSQL operator for the spruyt-labs cluster, managing database instances for various applications.

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

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [CNPG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
