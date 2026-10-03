# Vertical Pod Autoscaler - Automated Resource Right-Sizing

## Overview

Sizes workload requests from observed usage. Every VPA object in the repo uses `updateMode: "Initial"` or `"Off"` - none use `"Auto"` - so the updater never evicts; the admission webhook applies recommendations only when a pod is created. Initial-mode VPAs set `controlledValues: RequestsOnly`, because VPA otherwise scales limits proportionally and produced absurdly low memory limits.

The recommender loads 14 days of history from VictoriaMetrics at startup (`--storage=prometheus`) and takes live samples from metrics-server, so recommendations survive recommender restarts without a warm-up period.

History for pods that no longer exist is matched to a VPA through `kube_pod_labels`. This depends on `kube-state-metrics.metricLabelsAllowlist: [pods=[*]]` in victoria-metrics-k8s-stack and `--pod-label-prefix=label_` here. kube-state-metrics sanitizes label keys (`app.kubernetes.io/name` becomes `app_kubernetes_io_name`), so the `--metric-for-pod-labels` query uses MetricsQL `label_move` to
restore the keys VPA target selectors use. A target that selects on a dotted or dashed key missing from that list silently loses deleted-pod history; add a pair for it. This needs VPA's `prometheus/common` to accept UTF-8 label names (default since v0.62). The kubelet `/metrics/resource` scrape is disabled because its container CPU/memory series duplicate `/metrics/cadvisor`, and the recommender
discards the second copy as out-of-order samples.

## Operations

### CRD ownership

The chart templates the VPA CRDs under `templates/crds/`, so the CRDs and the controller images move together as one version and upgrade with the release. They carry `helm.sh/resource-policy: keep`, so uninstalling the release leaves the CRDs -- and every `VerticalPodAutoscaler` object across the cluster -- intact. Gate them with `crds.enabled` / `crds.keep` if that ever needs to change.

The HelmRelease still sets `install.crds` and `upgrade.crds` to `CreateReplace`; with no `crds/` directory left in the chart, those are inert for this release.

Chart 0.12.0 moved the CRDs out of `crds/`, which means Helm has to adopt two objects it did not previously own. Flux's helm-controller enables take-ownership by default, so the adoption is automatic. Setting `disableTakeOwnership: true` on this HelmRelease would break upgrades with an `invalid ownership metadata` error.

Talos also seeds the CRD at bootstrap via `talos/patches/control-plane/07-extra-manifests.yaml`, because Flux applies ~100 `VerticalPodAutoscaler` objects across app directories before this release reconciles. That URL is a write-once bootstrap seed: bumping it has no effect on a running cluster.

Renovate tracks its tag from the `# renovate:` annotation above it, against `kubernetes/autoscaler` release tags -- which are cut independently of chart releases, so the seed tag is *not* the chart's appVersion and should not be hand-edited to match it. The seed is gated on dependency dashboard approval so it cannot get ahead of the chart: if it did, a fresh bootstrap would seed the newer CRD,
create the VPA objects against it, then have the chart adopt and overwrite it with the older CRD underneath them. Approve a seed bump only once the chart has shipped the matching appVersion.

### Webhook certificate

cert-manager owns the webhook cert, not the chart's `certGen` Job. `createSelfSignedIssuer` produces a self-signed `Issuer`, a CA `Certificate`, a CA `Issuer` and the leaf `Certificate` (secret `vpa-tls-certs`), rotating on a 168h/24h schedule. The `MutatingWebhookConfiguration` carries `cert-manager.io/inject-ca-from`, so cainjector maintains the caBundle.

The admission controller runs with `--register-webhook=false`; Helm owns `vertical-pod-autoscaler-webhook-config`. If a self-registered `vpa-webhook-config` ever reappears (for example after running the controller with default flags), it is unmanaged, carries a stale caBundle and fails TLS on every pod CREATE - delete it.

### Metrics

The chart ships no metrics Services. Each component names its metrics container port `prometheus` (recommender 8942, updater 8943, admission controller 8944), so a single `VMPodScrape` covers all three pods.

### PodDisruptionBudgets

Disabled on all three components. Each runs a single replica, and the chart's default `minAvailable: 1` PDB on a 1-replica Deployment blocks node drains, which would break Talos upgrades.

## Troubleshooting

1. **VPA recommendations not appearing**

   - **Symptom**: `kubectl describe vpa` shows no recommendations for a new workload
   - **Resolution**: A workload with no history in VictoriaMetrics needs time to accumulate samples. For an existing workload, check the recommender logs for Prometheus query errors and the egress CNP to vmsingle on 8428.

2. **Pods created without VPA-applied requests**

   - **Symptom**: New pods use their manifest requests despite an `Initial`-mode VPA
   - **Resolution**: `failurePolicy: Ignore` makes webhook failures silent. Check that `vertical-pod-autoscaler-webhook-cert` is `READY=True`, that the `MutatingWebhookConfiguration` caBundle is populated, and that the CNP allows webhook ingress from the API server on port 8000.

## References

- [Kubernetes VPA Documentation](https://kubernetes.io/docs/concepts/workloads/autoscaling/)
- [Upstream Chart](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler/charts/vertical-pod-autoscaler)
- [VPA Flags](https://github.com/kubernetes/autoscaler/blob/master/vertical-pod-autoscaler/docs/flags.md)
