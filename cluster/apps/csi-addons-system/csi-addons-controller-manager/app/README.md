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

## Directory Layout

```yaml
csi-addons-controller-manager/
├── app/
│   ├── csi-addons-config.yaml        # Configuration for timeouts and concurrency
│   ├── kustomization.yaml            # Kustomize configuration
│   ├── rbac.yaml                     # RBAC permissions for controller
│   ├── setup-controller.yaml         # Controller deployment and config
│   └── README.md                     # This file
├── ks.yaml                           # Kustomization configuration
└── README.md                         # This file (symlink)
```

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

### Decision Trees

```yaml
# CSI Addons operational decision tree
start: "csi_addons_health_check"
nodes:
  csi_addons_health_check:
    question: "Is CSI Addons controller healthy?"
    command: "kubectl get pods -n csi-addons-system --no-headers | grep 'Running'"
    yes: "csi_addons_healthy"
    no: "investigate_issue"
  investigate_issue:
    action: "kubectl describe pods -n csi-addons-system | grep -A 10 'Events'"
    next: "analyze_root_cause"
  analyze_root_cause:
    question: "What is the root cause?"
    options:
      csi_driver_issue: "CSI driver compatibility problem"
      rbac_issue: "RBAC permissions issue"
      config_error: "Configuration error"
      resource_constraint: "Resource constraints"
  csi_driver_issue:
    action: "Verify CSI driver supports addons features: kubectl get csidrivers"
    next: "apply_fix"
  rbac_issue:
    action: "Check service account permissions: kubectl auth can-i create reclaimspacejobs --as=system:serviceaccount:csi-addons-system:csi-addons-controller-manager"
    next: "apply_fix"
  config_error:
    action: "Review config map settings: kubectl get configmap csi-addons-config -n csi-addons-system -o yaml"
    next: "apply_fix"
  resource_constraint:
    action: "Check resource usage: kubectl top pods -n csi-addons-system"
    next: "apply_fix"
  apply_fix:
    action: "Apply appropriate remediation using Flux reconciliation"
    next: "verify_fix"
  verify_fix:
    question: "Is issue resolved?"
    command: "kubectl get pods -n csi-addons-system --no-headers | grep 'Running'"
    yes: "csi_addons_healthy"
    no: "escalate"
  escalate:
    action: "Escalate with comprehensive diagnostics"
    next: "end"
  csi_addons_healthy:
    action: "CSI Addons verified healthy"
    next: "end"
end: "end"
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

### Cross-Service Dependencies

```yaml
# CSI Addons cross-service dependencies
service_dependencies:
  csi-addons-controller-manager:
    depends_on:
      - kube-system/cilium (for network fencing)
      - Storage CSI drivers (for addon features)
    depended_by:
      - Storage-intensive applications requiring reclaimspace
      - Systems using volume replication
    critical_path: false
    health_check_command: "kubectl get pods -n csi-addons-system --no-headers | grep 'Running'"
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

### MCP Integration

#### Library Usage Patterns

CSI Addons documentation is not currently in the approved Context7 library catalog. For documentation needs:

- Use manual review of [CSI Addons GitHub repository](https://github.com/csi-addons/kubernetes-csi-addons)
- Version: `v0.13.0`
- Consider adding to `context7-libraries.json` for future automated lookups

#### Citation Workflow

When referencing CSI Addons documentation:

1. Record manual source: GitHub repository at specific version
2. Include relevant excerpts in change notes
3. Note any assumptions made during manual review
4. Escalate to documentation governance if automated tools are needed

## References

- [CSI Addons Documentation](https://github.com/csi-addons/kubernetes-csi-addons)
- [Reclaimspace Documentation](https://github.com/csi-addons/kubernetes-csi-addons/blob/v0.13.0/docs/reclaimspace.md)
- [CSI Specification](https://github.com/container-storage-interface/spec)
- [Flux CD Documentation](https://fluxcd.io/flux/)
