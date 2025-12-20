# Snapshot Controller - Volume Snapshot Management

## Overview

Snapshot Controller provides Kubernetes-native volume snapshot capabilities, enabling point-in-time copies of persistent volumes. It serves as the snapshot management solution for the spruyt-labs cluster, providing backup and restore functionality for persistent volumes.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Storage class configured for persistent volumes
- Volume snapshot CRDs available
- Proper RBAC permissions

## Operation

### Procedures

1. **Volume snapshot management**:

```bash
# Create volume snapshot
kubectl apply -f volumesnapshot.yaml

# Check snapshot status
kubectl get volumesnapshots -A
```

2. **Snapshot class management**:

```bash
# Check snapshot classes
kubectl get volumesnapshotclasses

# Create snapshot class
kubectl apply -f volumesnapshotclass.yaml
```

3. **Restore operations**:

```bash
# Create volume from snapshot
kubectl apply -f pvc-from-snapshot.yaml

# Check restore status
kubectl get pvc -A
```

## Troubleshooting

### Common Issues

1. **CRD registration failures**:

   - **Symptom**: Volume snapshot CRDs not available
   - **Diagnosis**: Check CRD installation and API server
   - **Resolution**: Reinstall CRDs and verify API server connectivity

2. **RBAC permission errors**:

   - **Symptom**: Access denied errors in logs
   - **Diagnosis**: Check RBAC roles and bindings
   - **Resolution**: Verify cluster roles and service account permissions

3. **Storage backend connectivity issues**:
   - **Symptom**: Snapshot creation failures
   - **Diagnosis**: Check storage backend connectivity
   - **Resolution**: Verify storage provider configuration and network access

## Maintenance

### Updates

```bash
# Update snapshot controller
kubectl apply -k . --force
```

### Snapshot Management

```bash
# Check volume snapshots
kubectl get volumesnapshots -A

# Check snapshot classes
kubectl get volumesnapshotclasses
```

## References

- [Kubernetes Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
- [Snapshot Controller Documentation](https://github.com/kubernetes-csi/external-snapshotter)
- [Kubernetes Storage Documentation](https://kubernetes.io/docs/concepts/storage/)
