# flux-operator - Flux Operator

## Overview

Flux Operator is a Kubernetes operator that manages Flux deployments using custom resources. It provides a declarative way to manage Flux instances and their components, enabling GitOps workflows for continuous delivery in the spruyt-labs homelab infrastructure.

## Prerequisites

- Kubernetes cluster with proper RBAC configured

## Operation

### Procedures

1. **Flux operator management**:

```bash
# Check flux-operator service status
kubectl get pods -n flux-system

# Verify operator reconciliation
kubectl logs -n flux-system <operator-pod-name> | grep "reconciliation"

# Check operator events
kubectl get events -n flux-system | grep flux-operator
```

2. **Configuration management**:

```bash
# Check current configuration
kubectl get configmap -n flux-system

# Verify operator configuration
kubectl get fluxoperators -A -o yaml
```

3. **Performance monitoring**:

   ```bash
   # Check operator reconciliation status
   kubectl logs -n flux-system <operator-pod-name> | grep "reconciliation"

   # Monitor operator performance
   kubectl top pods -n flux-system
   ```

### Validation

Run the following commands to validate the procedures:

```bash
# Validate flux-operator management
kubectl get pods -n flux-system --no-headers | grep 'Running'

# Expected: Flux operator pods running

# Validate configuration management
kubectl get configmap -n flux-system

# Expected: Configuration maps listed

# Validate performance monitoring
kubectl top pods -n flux-system

# Expected: Resource usage displayed
```

## Troubleshooting

### Common Issues

1. **Git repository connectivity failures**:

   - **Symptom**: Operator unable to access Git repository
   - **Diagnosis**: Check Git repository connectivity and credentials
   - **Resolution**: Verify SSH keys and repository URLs

2. **RBAC permission errors**:

   - **Symptom**: Access denied errors in logs
   - **Diagnosis**: Check RBAC permissions and service accounts
   - **Resolution**: Verify cluster roles and role bindings

3. **Reconciliation delays**:

   - **Symptom**: Slow operator reconciliation
   - **Diagnosis**: Check operator performance and resource usage
   - **Resolution**: Verify operator resources and network latency

4. **Configuration errors**:

   - **Symptom**: Operator service not starting
   - **Diagnosis**: Check configuration syntax and operator parameters
   - **Resolution**: Verify values.yaml configuration

## Maintenance

### Updates

```bash
# Update flux-operator using Flux
flux reconcile kustomization flux-operator --with-source
```

### Configuration Management

```bash
# Update flux-operator configuration
flux reconcile kustomization flux-operator --with-source

# Verify configuration changes
kubectl logs -n flux-system <operator-pod-name> | grep "configuration"
```

## References

- [Flux Operator Documentation](https://fluxcd.io/flux/)
- [Flux GitOps Toolkit](https://fluxcd.io/flux/guides/)
- [Kubernetes Operator Framework](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [Flux Helm Chart](https://github.com/fluxcd/flux2)
