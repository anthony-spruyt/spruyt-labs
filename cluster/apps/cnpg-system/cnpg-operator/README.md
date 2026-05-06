# CloudNativePG Operator - PostgreSQL Management

## Overview

CloudNativePG Operator provides comprehensive PostgreSQL management for Kubernetes, offering high availability, backup, restore, and monitoring capabilities. It serves as the primary PostgreSQL operator for the cluster, managing database instances for various applications.

## kubectl cnpg Plugin

Install the CNPG kubectl plugin for enhanced cluster management:

```bash
task dev-env:install-cnpg
```

Common operations:

```bash
# Check cluster status (detailed view)
kubectl cnpg status <cluster-name> -n <namespace>

# Restart cluster (preferred over pod deletion for secret rotation, config changes)
kubectl cnpg restart <cluster-name> -n <namespace>

# Trigger manual backup
kubectl cnpg backup <cluster-name> -n <namespace>

# Reload configuration without restart
kubectl cnpg reload <cluster-name> -n <namespace>
```

## Troubleshooting

1. **PostgreSQL cluster stuck initializing**

   - **Symptom**: Clusters stuck in initializing state
   - **Resolution**: Verify storage class provisioning and network policies

1. **Scheduled backups not running**

   - **Symptom**: Backups not executing on schedule
   - **Resolution**: Verify backup storage credentials and schedules

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/)
- [CNPG GitHub](https://github.com/cloudnative-pg/cloudnative-pg)
