# Spegel - Local Container Registry Mirror

## Overview

Spegel is a local container registry mirror that caches and serves container images within the Kubernetes cluster. In the spruyt-labs homelab infrastructure, Spegel reduces external network dependencies and improves image pull performance by serving frequently used images locally.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Sufficient storage for cached container images
- Network connectivity for registry operations
- Proper RBAC permissions for image operations
- Container runtime with registry support

## Operation

### Procedures

1. **Image caching management**:

   ```bash
   # Check cached images
   kubectl exec -it <spegel-pod> -n spegel -- spegel list

   # Monitor cache performance
   kubectl logs -n spegel <spegel-pod> | grep "cache"
   ```

2. **Registry operations**:

   ```bash
   # Check registry health
   kubectl exec -it <spegel-pod> -n spegel -- spegel health

   # Monitor pull operations
   kubectl logs -n spegel <spegel-pod> | grep "pull"
   ```

3. **Configuration updates**:

   ```bash
   # Update Spegel configuration
   # Edit values.yaml, commit, then: flux reconcile kustomization spegel --with-source

   # Restart pods for configuration changes
   kubectl rollout restart deployment spegel -n spegel
   ```

## Troubleshooting

### Common Issues

1. **Cache consistency problems**:

   - **Symptom**: Inconsistent image availability
   - **Diagnosis**: Check cache verification logs
   - **Resolution**: Clear and rebuild cache

2. **Storage capacity issues**:

   - **Symptom**: Cache eviction or storage errors
   - **Diagnosis**: Monitor storage usage
   - **Resolution**: Scale storage or clean up unused images

3. **Network connectivity problems**:

   - **Symptom**: Image pull failures
   - **Diagnosis**: Test network connectivity
   - **Resolution**: Verify network policies and DNS

4. **Authentication failures**:

   - **Symptom**: Registry authentication errors
   - **Diagnosis**: Check authentication configuration
   - **Resolution**: Verify credentials and RBAC policies

## Maintenance

### Updates

```bash
# Update Spegel using Flux
flux reconcile kustomization spegel --with-source

# Check update status
kubectl get helmreleases -n spegel
```

### Cache Management

```bash
# Clear cache
kubectl exec -it <spegel-pod> -n spegel -- spegel clear

# Rebuild cache
kubectl exec -it <spegel-pod> -n spegel -- spegel rebuild
```

## References

- [Spegel Documentation](https://github.com/XenitAB/spegel)
- [Container Registry Specification](https://github.com/opencontainers/distribution-spec)
- [Kubernetes Image Pull Secrets](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- [Registry Performance Tuning](https://docs.docker.com/registry/)
