# Flux Instance - GitOps Continuous Delivery

## Overview

Flux is a GitOps continuous delivery solution that automates the deployment and management of Kubernetes resources. It provides declarative infrastructure management by synchronizing the cluster state with the Git repository, enabling continuous delivery and drift detection.

## Prerequisites

- Kubernetes cluster with proper RBAC configured
- flux-operator deployed and operational (Flux dependsOn: flux-operator)
- Git repository accessible from cluster
- SSH keys or credentials for Git access
- Proper network connectivity to Git repository

## Operation

### Procedures

1. **Git repository management**:

```bash
# Check source status
flux get sources -A

# Reconcile source
flux reconcile source git <name>
```

2. **Kustomization monitoring**:

```bash
# Check kustomization status
flux get kustomizations -A

# Reconcile kustomization
flux reconcile kustomization <name> --with-source
```

3. **Drift detection**:

   ```bash
   # Check all kustomizations for drift
   flux get kustomizations -A

   # Force reconciliation of a specific kustomization
   flux reconcile kustomization <name> --with-source
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate Git repository management
flux get sources -A

# Expected: Sources listed with ready status

# Validate kustomization monitoring
flux get kustomizations -A

# Expected: Kustomizations listed with ready status

# Validate drift detection
flux get kustomizations -A

# Expected: No drift detected or reconciliation in progress
```

## Troubleshooting

### Common Issues

1. **Git repository connectivity failures**:

   - **Symptom**: Sources not synchronizing
   - **Diagnosis**: Check Git repository access and credentials
   - **Resolution**: Verify SSH keys and repository URLs

2. **Kustomization reconciliation errors**:

   - **Symptom**: Kustomizations stuck in progress
   - **Diagnosis**: Check kustomization configuration and resource validity
   - **Resolution**: Verify YAML syntax and resource definitions

3. **RBAC permission errors**:
   - **Symptom**: Access denied errors in logs
   - **Diagnosis**: Check RBAC permissions and service accounts
   - **Resolution**: Verify cluster roles and role bindings

## Maintenance

### Updates

```bash
# Update Flux instance using Flux (uses OCIRepository, not a Helm repo)
flux reconcile kustomization flux-instance --with-source
```

### GitOps Management

```bash
# Check Flux version
flux version
```

## References

- [Flux Documentation](https://fluxcd.io/flux/)
- [Flux GitOps Toolkit](https://fluxcd.io/flux/guides/)
- [Flux Helm Chart](https://github.com/fluxcd/flux2)
