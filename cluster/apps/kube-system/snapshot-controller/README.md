# Snapshot Controller - Volume Snapshot Management

## Overview

Snapshot Controller provides Kubernetes-native volume snapshot capabilities, enabling point-in-time copies of persistent volumes. It serves as the snapshot management solution for the spruyt-labs cluster, providing backup and restore functionality for persistent volumes.

## Directory Layout

```yaml
snapshot-controller/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── rbac-snapshot-controller.yaml # RBAC configuration
│   ├── setup-snapshot-controller.yaml # Setup configuration
│   └── kustomizeconfig.yaml        # Kustomize config
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

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

### Decision Trees

```yaml
# Snapshot controller decision tree
start: "snapshot_controller_health_check"
nodes:
  snapshot_controller_health_check:
    question: "Is snapshot controller healthy?"
    command: "kubectl get pods -n kube-system -l app=snapshot-controller --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "snapshot_controller_healthy"
  investigate_issue:
    action: "kubectl describe pods -n kube-system -l app=snapshot-controller | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      crd_registration: "CRD registration failure"
      rbac_permission: "RBAC permission problem"
      storage_backend: "Storage backend issue"
      resource_constraint: "Resource limitation"
  crd_registration:
    action: "Check CRD registration: kubectl get crds | grep snapshot"
    next: "apply_fix"
  rbac_permission:
    action: "Verify RBAC configuration: kubectl get clusterroles | grep snapshot"
    next: "apply_fix"
  storage_backend:
    action: "Check storage backend connectivity and configuration"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n kube-system -l app=snapshot-controller --no-headers | grep 'Running'"
    yes: "snapshot_controller_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  snapshot_controller_healthy:
    action: "Snapshot controller verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Snapshot controller cross-service dependencies
service_dependencies:
  snapshot-controller:
    depends_on:
      - rook-ceph/rook-ceph
    depended_by:
      - All workloads requiring volume snapshots
      - All applications using persistent volumes
      - All backup and restore operations
    critical_path: true
    health_check_command: "kubectl get pods -n kube-system -l app=snapshot-controller --no-headers | grep 'Running'"
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

### MCP Integration

- **Library ID**: `kubernetes-snapshot-controller`
- **Version**: `v6.2.2`
- **Usage**: Volume snapshot management and automation
- **Citation**: Use `resolve-library-id` for snapshot controller configuration and troubleshooting

## References

- [Kubernetes Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
- [Snapshot Controller Documentation](https://github.com/kubernetes-csi/external-snapshotter)
- [Kubernetes Storage Documentation](https://kubernetes.io/docs/concepts/storage/)
