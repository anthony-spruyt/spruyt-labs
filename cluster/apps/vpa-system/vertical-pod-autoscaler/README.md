# Vertical Pod Autoscaler - Automated Resource Right-Sizing

## Overview

VPA automatically recommends resource requests and limits for workloads based on actual usage metrics. Workloads run with `updateMode: "Initial"` or `"Off"` -- no workload uses `"Auto"`, so the updater never evicts. Priority tier: `high-priority`.

Components:

- **Recommender**: Watches all workloads, generates resource recommendations
- **Updater**: Evicts pods needing updates (inactive without `updateMode: "Auto"`)
- **Admission Controller**: Mutating webhook that sets resources on pod creation (applies with `updateMode: "Initial"`)

> **Note**: The Flux Kustomization lives in flux-system but the HelmRelease and workloads are deployed to the vpa-system namespace via `targetNamespace` in ks.yaml.

## Prerequisites

- `cert-manager` -- issues the admission controller's webhook certificate

## Operations

### CRD ownership

The chart ships the VPA CRD in its own `crds/` directory, so the CRD and the controller images move together as one version. Plain Helm never upgrades `crds/`, so the HelmRelease sets `install.crds` and `upgrade.crds` to `CreateReplace`.

Talos also seeds the CRD at bootstrap via `talos/patches/control-plane/extra-manifests.yaml`, because Flux applies ~100 `VerticalPodAutoscaler` objects across app directories before this release reconciles. That URL is a write-once bootstrap seed -- keep its tag matching the chart's appVersion.

### Webhook certificate

cert-manager owns the webhook cert, not the chart's `certGen` Job. `createSelfSignedIssuer` produces a self-signed `Issuer`, a CA `Certificate`, a CA `Issuer` and the leaf `Certificate` (secret `vpa-tls-certs`), rotating on a 168h/24h schedule. The `MutatingWebhookConfiguration` carries `cert-manager.io/inject-ca-from`, so cainjector maintains the caBundle.

The admission controller runs with `--register-webhook=false`; Helm owns `vertical-pod-autoscaler-webhook-config`.

The previous chart let the controller self-register `vpa-webhook-config`, which left an unmanaged cluster-scoped object with a stale caBundle. `failurePolicy: Ignore` keeps it harmless, but it fails TLS on every pod CREATE, so delete it once after the migration:

```bash
kubectl delete mutatingwebhookconfiguration vpa-webhook-config
```

### Metrics

The chart ships no metrics Services. Each component names its metrics container port `prometheus` (recommender 8942, updater 8943, admission controller 8944), so a single `VMPodScrape` covers all three pods.

### PodDisruptionBudgets

Disabled on all three components. Each runs a single replica, and the chart's default `minAvailable: 1` PDB on a 1-replica Deployment blocks node drains, which would break Talos upgrades.

## Troubleshooting

1. **VPA recommendations not appearing**

   - **Symptom**: `kubectl describe vpa` shows no recommendations
   - **Resolution**: Recommender needs ~24h of metrics data. Check recommender logs for errors.

2. **Pods created without VPA-applied requests**

   - **Symptom**: New pods use their manifest requests despite an `Initial`-mode VPA
   - **Resolution**: `failurePolicy: Ignore` makes webhook failures silent. Check that `vertical-pod-autoscaler-webhook-cert` is `READY=True`, that the `MutatingWebhookConfiguration` caBundle is populated, and that the CNP allows webhook ingress from the API server on port 8000.

## References

- [Kubernetes VPA Documentation](https://kubernetes.io/docs/concepts/workloads/autoscaling/)
- [Upstream Chart](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler/charts/vertical-pod-autoscaler)
- [VPA Flags](https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/docs/flags.md)
