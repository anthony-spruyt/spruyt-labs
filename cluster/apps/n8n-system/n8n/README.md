# n8n - Workflow Automation

## Overview

n8n is a workflow automation tool that connects various applications and services through visual workflows. It provides a low-code platform for integrating APIs, databases, and cloud services in the spruyt-labs homelab infrastructure, enabling powerful automation capabilities.

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

2. **Database operations** - See [CNPG operator docs](../../cnpg-system/cnpg-operator/README.md#kubectl-cnpg-plugin) for `kubectl cnpg` plugin usage. Cluster name: `n8n-cnpg-cluster`

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

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n API Documentation](https://docs.n8n.io/api/)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/)
