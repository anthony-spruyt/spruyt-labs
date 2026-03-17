# Vertical Pod Autoscaler - Automated Resource Right-Sizing

## Overview

VPA automatically recommends resource requests and limits for workloads based on actual usage metrics. Deployed with `updateMode: "Off"` — generates recommendations only, does not modify pods. Priority tier: `high-priority`.

Components:
- **Recommender**: Watches all workloads, generates resource recommendations
- **Updater**: Evicts pods needing updates (inactive with `updateMode: "Off"`)
- **Admission Controller**: Mutating webhook that sets resources on pod creation (inactive with `updateMode: "Off"`)

> **Note**: The Flux Kustomization lives in flux-system but the HelmRelease and workloads are deployed to the vpa-system namespace via `targetNamespace` in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n vpa-system
flux get helmrelease -n vpa-system vertical-pod-autoscaler

# View VPA recommendations for all workloads
kubectl describe vpa -A

# Force reconcile
flux reconcile kustomization vertical-pod-autoscaler --with-source

# View logs
kubectl logs -n vpa-system -l app.kubernetes.io/name=vertical-pod-autoscaler
```

### Enabling Auto-Updates

To enable VPA auto-updates for a specific workload, create a `VerticalPodAutoscaler` resource with `updateMode: "Auto"` targeting that workload. Start with low-risk, stateless workloads.

## Troubleshooting

### Common Issues

1. **VPA recommendations not appearing**
   - **Symptom**: `kubectl describe vpa` shows no recommendations
   - **Resolution**: Recommender needs ~24h of metrics data. Check recommender logs for errors.

2. **Webhook failures after enabling Auto mode**
   - **Symptom**: Pods fail to create with admission webhook errors
   - **Resolution**: Check admission-controller pod health and CNP allows webhook ingress from API server on port 8000.

## References

- [Kubernetes VPA Documentation](https://kubernetes.io/docs/concepts/workloads/autoscaling/)
- [Cowboysysop Chart](https://github.com/cowboysysop/charts/tree/master/charts/vertical-pod-autoscaler)
