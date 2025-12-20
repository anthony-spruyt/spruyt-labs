# reloader - Configuration Reloader

## Overview

Reloader is a Kubernetes controller that automatically reloads configurations when ConfigMaps or Secrets are updated. It monitors changes to configuration resources and triggers pod restarts or rolling updates to ensure applications use the latest configuration in the spruyt-labs homelab infrastructure.

## Prerequisites

- Kubernetes cluster with Flux CD installed
- Applications that need automatic configuration reloading
- Proper RBAC permissions for reloader to monitor resources
- ConfigMaps and Secrets that need to be watched

## Operation

### Procedures

1. **Configuration monitoring**:

   ```bash
   # Check reloader service status
   kubectl get pods -n reloader

   # Verify watched resources
   kubectl logs -n reloader <pod-name> | grep "watching"

   # Check reloading events
   kubectl get events -n reloader
   ```

2. **Annotation management**:

   ```bash
   # Add new annotation to deployment
   kubectl annotate deployment <deployment-name> \
     secret.reloader.stakater.com/reload="<secret-name>"

   # Verify annotations
   kubectl get deployment <deployment-name> -o json | jq '.metadata.annotations'
   ```

## Troubleshooting

### Common Issues

1. **RBAC permission errors**:

   - **Symptom**: Reloader unable to watch resources
   - **Diagnosis**: Check RBAC permissions and service accounts
   - **Resolution**: Verify cluster roles and role bindings

2. **Configuration reloading failures**:

   - **Symptom**: Pods not restarting after config changes
   - **Diagnosis**: Check reloader logs and annotations
   - **Resolution**: Verify annotation syntax and resource names

3. **Resource constraints**:

   - **Symptom**: Pods in Pending state or frequent restarts
   - **Diagnosis**: Check resource requests vs available cluster resources
   - **Resolution**: Adjust resource limits or scale cluster

4. **Event processing delays**:

   - **Symptom**: Slow configuration reloading
   - **Diagnosis**: Check reloader performance and event queue
   - **Resolution**: Verify reloader resources and event processing

## Maintenance

### Updates

```bash
# Update reloader using Flux
flux reconcile kustomization reloader --with-source
```

### Annotation Management

```bash
# Add new reloader annotation
kubectl annotate deployment <deployment-name> \
  configmap.reloader.stakater.com/reload="<configmap-name>"

# Remove reloader annotation
kubectl annotate deployment <deployment-name> \
  configmap.reloader.stakater.com/reload-
```

## References

- [Reloader Documentation](https://github.com/stakater/Reloader)
- [Reloader Helm Chart](https://github.com/stakater/Reloader/tree/master/deployments/kubernetes/chart/reloader)
- [Flux CD Documentation](https://fluxcd.io/flux/)
- [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
