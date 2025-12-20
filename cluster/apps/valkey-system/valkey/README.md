# Valkey - High-Performance Key-Value Store

## Overview

Valkey is a high-performance, open-source key-value store compatible with Redis protocols. In the spruyt-labs homelab infrastructure, Valkey serves as the primary caching and data storage solution for various applications, providing low-latency access to frequently used data.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Storage class configured for persistent volumes
- Network connectivity between application pods
- Proper RBAC permissions for Valkey operations
- Monitoring and observability stack deployed

## Operation

### Procedures

1. **Cluster management**:

```bash
# Check cluster status
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli cluster info

# Monitor cluster health
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli cluster nodes
```

2. **Performance monitoring**:

```bash
# Check memory usage
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli info memory

# Monitor connections
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli info clients
```

3. **Backup operations**:

```bash
# Trigger manual backup
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli save

# Check backup status
kubectl exec -it valkey-0 -n valkey-system -- valkey-cli lastsave
```

## Troubleshooting

### Common Issues

1. **Memory pressure and eviction**:

   - **Symptom**: High memory usage, frequent evictions
   - **Diagnosis**: Check memory metrics and eviction statistics
   - **Resolution**: Adjust maxmemory policy or scale cluster

2. **Network connectivity problems**:

   - **Symptom**: Connection timeouts or failures
   - **Diagnosis**: Test network connectivity and DNS resolution
   - **Resolution**: Verify Cilium network policies and service discovery

3. **Persistence failures**:

   - **Symptom**: Data loss after pod restarts
   - **Diagnosis**: Check persistent volume claims and storage
   - **Resolution**: Verify Rook Ceph storage provisioning

4. **Replication issues**:

   - **Symptom**: Cluster nodes not synchronizing
   - **Diagnosis**: Check cluster status and replication
   - **Resolution**: Verify cluster configuration and connectivity

## Maintenance

### Updates

```bash
# Update Valkey using Flux
flux reconcile kustomization valkey --with-source

# Check update status
kubectl get helmreleases -n valkey-system
```

### Configuration Management

```bash
# Update configuration (edit values.yaml, commit, then reconcile)
flux reconcile kustomization valkey --with-source

# Or force pod restart after config changes
kubectl rollout restart statefulset valkey -n valkey-system
```

## References

- [Valkey Documentation](https://valkey.io/)
- [Valkey Helm Chart](https://github.com/valkey-io/valkey-helm)
- [Redis Compatibility Guide](https://redis.io/docs/)
- [Kubernetes Stateful Applications](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
