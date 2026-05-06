# Metrics Server - Kubernetes Resource Metrics API

## Overview

Metrics Server provides the `metrics.k8s.io` Kubernetes API, exposing real-time container and node CPU/memory usage. Used by VPA recommender, HPA, `kubectl top`, and Headlamp resource display.

Deployed with 2 replicas and `--kubelet-insecure-tls` for Talos Linux compatibility (self-signed kubelet serving certs).

## Prerequisites

- kyverno-policies (from ks.yaml dependsOn)

## Troubleshooting

### Common Issues

1. **Metrics API unavailable**

   - **Symptom**: `kubectl top` returns "Metrics API not available"
   - **Resolution**: Check APIService status: `kubectl get apiservice v1beta1.metrics.k8s.io -o yaml`. Verify pods are Running and endpoints exist.

1. **TLS errors to kubelets**

   - **Symptom**: Logs show `x509: cannot validate certificate` errors
   - **Resolution**: Ensure `--kubelet-insecure-tls` is set in values.yaml `args`. Required for Talos Linux.

## References

- [Metrics Server GitHub](https://github.com/kubernetes-sigs/metrics-server)
- [Kubernetes Metrics API](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
