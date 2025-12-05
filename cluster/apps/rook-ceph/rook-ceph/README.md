# Rook Ceph - Storage Orchestration

## Overview

Rook Ceph provides distributed storage orchestration for Kubernetes, delivering block, file, and object storage services. It serves as the primary storage solution for the spruyt-labs cluster, providing persistent volumes, object storage, and data protection capabilities.

## Directory Layout

```yaml
rook-ceph/
├── app/
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── kustomizeconfig.yaml        # Kustomize config
│   ├── release.yaml                # Helm release configuration
│   └── values.yaml                 # Helm values
├── ks.yaml                         # Kustomization configuration
└── README.md                       # This file
```

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Raw block devices available on nodes
- Storage class configured
- Network connectivity between nodes

## Operation

### Procedures

1. **Storage class management**:

```bash
# Check storage classes
kubectl get storageclasses

# Set default storage class
kubectl patch storageclass <name> -p '{\"metadata\": {\"annotations\":{\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}'
```

2. **Ceph cluster monitoring**:

```bash
# Check Ceph cluster status
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph status

# Check OSD status
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph osd status
```

3. **Persistent volume management**:

   ```bash
   # Check persistent volumes
   kubectl get pv

   # Check persistent volume claims
   kubectl get pvc -A
   ```

### Decision Trees

```yaml
# Rook Ceph operational decision tree
start: "rook_ceph_health_check"
nodes:
  rook_ceph_health_check:
    question: "Is Rook Ceph healthy?"
    command: "kubectl get pods -n rook-ceph --no-headers | grep -v 'Running'"
    yes: "investigate_issue"
    no: "rook_ceph_healthy"
  investigate_issue:
    action: "kubectl describe pods -n rook-ceph | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      osd_failure: "OSD failure or degradation"
      network_connectivity: "Network connectivity issue"
      storage_capacity: "Storage capacity problem"
      resource_constraint: "Resource limitation"
  osd_failure:
    action: "Check OSD status: kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph osd status"
    next: "apply_fix"
  network_connectivity:
    action: "Investigate network connectivity between nodes"
    next: "apply_fix"
  storage_capacity:
    action: "Check storage capacity: kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph df"
    next: "apply_fix"
  resource_constraint:
    action: "Adjust resource requests/limits in values.yaml"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n rook-ceph --no-headers | grep 'Running'"
    yes: "rook_ceph_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  rook_ceph_healthy:
    action: "Rook Ceph verified healthy"
    next: "end"
end: "end"
```

### Cross-Service Dependencies

```yaml
# Rook Ceph cross-service dependencies
service_dependencies:
  rook-ceph:
    depends_on:
      - kube-system/cilium
    depended_by:
      - All workloads requiring persistent storage
      - All stateful applications
      - All applications using object storage
    critical_path: true
    health_check_command: "kubectl get pods -n rook-ceph --no-headers | grep 'Running'"
```

## Troubleshooting

### Common Issues

1. **OSD failures**:

   - **Symptom**: Ceph cluster in degraded state
   - **Diagnosis**: Check OSD status and node connectivity
   - **Resolution**: Verify node storage devices and network connectivity

2. **Storage capacity issues**:

   - **Symptom**: Persistent volume provisioning failures
   - **Diagnosis**: Check Ceph storage capacity
   - **Resolution**: Add storage capacity or clean up unused data

3. **Network connectivity problems**:
   - **Symptom**: OSDs unable to communicate
   - **Diagnosis**: Check network connectivity and Cilium network policies
   - **Resolution**: Verify network configuration and policies

## Maintenance

### Updates

```bash
# Update Rook Ceph Helm chart
helm repo update
helm upgrade rook-ceph rook-release/rook-ceph -n rook-ceph -f values.yaml
```

### Storage Management

```bash
# Check storage usage
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph df

# Check OSD utilization
kubectl exec -n rook-ceph deploy/rook-ceph-tools -- ceph osd df
```

### MCP Integration

- **Library ID**: `rook-ceph-storage-orchestration`
- **Version**: `v1.12.1`
- **Usage**: Distributed storage for Kubernetes
- **Citation**: Use `resolve-library-id` for Rook Ceph configuration and troubleshooting

## References

- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
- [Ceph Documentation](https://docs.ceph.com/)
- [Rook Ceph Helm Chart](https://github.com/rook/rook)
