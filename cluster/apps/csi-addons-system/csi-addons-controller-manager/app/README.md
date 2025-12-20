# CSI Addons Controller Manager - Storage Addons Management

## Overview

CSI Addons Controller Manager provides extended Container Storage Interface (CSI) capabilities for the spruyt-labs homelab infrastructure, enabling advanced storage operations beyond the standard CSI specification.
It is a Kubernetes controller that extends CSI drivers with additional capabilities not covered by the core CSI specification.
It provides APIs and controllers for operations like reclaiming unused space on storage volumes, managing network fences for storage isolation, and handling encryption key lifecycle management.

Objectives:

- Provide reclaimspace functionality for CSI volumes
- Manage network fencing for storage systems
- Handle encryption key rotation for encrypted volumes
- Support volume group replication operations
- Enable advanced storage management features

The controller manager runs as a deployment in the csi-addons-system namespace and manages custom resources for these extended operations.

## Prerequisites

- Kubernetes cluster with CSI drivers installed
- Flux CD for GitOps management
- Storage systems supporting CSI addons features
- Appropriate RBAC permissions for storage operations

### Validation

```bash
# Validate CSI Addons controller installation
kubectl get pods -n csi-addons-system

# Check controller manager status
kubectl get deployment csi-addons-controller-manager -n csi-addons-system

# Verify CSI addons CRDs
kubectl get crd | grep csiaddons
```

## Operation

All operations are performed declaratively through Flux-managed Kustomizations. Manual kubectl commands are only used for monitoring and validation, not for making changes.

### Procedures

All CSI Addons operations are managed declaratively through Flux Kustomizations. Create appropriate custom resources in YAML manifests committed to the repository.

1. **Reclaimspace operations**:

   - Add reclaimspace annotations to PVC YAML manifests to trigger space reclamation
   - Monitor ReclaimSpaceJob progress through kubectl

   ```bash
   # Monitor reclaimspace jobs
   kubectl get reclaimspacejobs -A
   ```

2. **Network fencing management**:

   ```bash
   # List network fence classes
   kubectl get networkfenceclasses

   # Check network fences
   kubectl get networkfences -A
   ```

3. **Encryption key rotation**:

   ```bash
   # Monitor key rotation jobs
   kubectl get encryptionkeyrotationjobs -A

   # Check rotation cron jobs
   kubectl get encryptionkeyrotationcronjobs -A
   ```

### Monitoring Commands

```bash
# Check controller manager health
kubectl get pods -n csi-addons-system --no-headers | grep 'Running'

# Monitor reclaimspace jobs
kubectl get reclaimspacejobs -A

# Check network fences
kubectl get networkfences -A

# Monitor encryption key rotation jobs
kubectl get encryptionkeyrotationjobs -A
```

## Troubleshooting

### Common Issues

1. **Reclaimspace job failures**:

   - **Symptom**: ReclaimSpaceJob stuck in pending or failed state
   - **Diagnosis**: Check CSI driver support and volume accessibility
   - **Resolution**: Verify volume exists and driver supports reclaimspace, then use `flux reconcile kustomization csi-addons-controller-manager --with-source`

2. **Network fence creation errors**:

   - **Symptom**: NetworkFence resources fail to create
   - **Diagnosis**: Check network policy configurations and Cilium setup
   - **Resolution**: Review network fence class configuration and Cilium network policies

3. **Encryption key rotation timeouts**:

   - **Symptom**: Key rotation jobs timeout
   - **Diagnosis**: Check storage system responsiveness and timeout configuration
   - **Resolution**: Adjust timeout settings in csi-addons-config ConfigMap

## Maintenance

### Updates

```bash
# Update CSI Addons controller using Flux
flux reconcile kustomization csi-addons-controller-manager --with-source
```

### Configuration Management

Configuration changes are made declaratively by editing the `csi-addons-config.yaml` file in the repository and committing changes. Flux automatically reconciles the configuration.

```bash
# Apply changes via Flux
flux reconcile kustomization csi-addons-controller-manager --with-source
```

### Backups

Configuration backups are maintained through Git version control. All configuration changes are committed to the repository.

For disaster recovery, restore configurations by ensuring the YAML manifests in the repository are up-to-date and reconciled via Flux.

## References

- [CSI Addons Documentation](https://github.com/csi-addons/kubernetes-csi-addons)
- [Reclaimspace Documentation](https://github.com/csi-addons/kubernetes-csi-addons/blob/v0.13.0/docs/reclaimspace.md)
- [CSI Specification](https://github.com/container-storage-interface/spec)
- [Flux CD Documentation](https://fluxcd.io/flux/)
