# plugin-barman-cloud - Barman Cloud Plugin

## Overview

Barman Cloud Plugin provides cloud storage integration for PostgreSQL backups managed by CloudNativePG. It enables backup and restore operations with cloud storage providers for enhanced data protection and disaster recovery capabilities.

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

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
