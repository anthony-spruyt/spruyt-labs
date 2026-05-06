# Reloader - Configuration Reloader

## Overview

Reloader is a Kubernetes controller that automatically triggers pod restarts when referenced ConfigMaps or Secrets are updated. Monitors changes to configuration resources and triggers rolling updates to ensure applications use the latest configuration.

## Troubleshooting

1. **Pods not restarting after config changes**

   - **Symptom**: ConfigMap/Secret updated but pods still running old config
   - **Resolution**: Verify annotation syntax on the Deployment/StatefulSet. Must be `secret.reloader.stakater.com/reload="<secret-name>"` or `configmap.reloader.stakater.com/reload="<configmap-name>"`. Check reloader logs for watch errors.

## References

- [Reloader Documentation](https://github.com/stakater/Reloader)
- [Reloader Helm Chart](https://github.com/stakater/Reloader/tree/master/deployments/kubernetes/chart/reloader)
