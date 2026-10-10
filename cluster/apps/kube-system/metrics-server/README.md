# Metrics Server - Resource Metrics API

## Overview

Serves `metrics.k8s.io` for the VPA recommender's live samples, the descheduler's `LowNodeUtilization` plugin, `kubectl top` and Headlamp.

## Operations

Talos runs kubelets with `serverTLSBootstrap: true`, and kubelet-csr-approver gets the serving certificates signed by the cluster CA with the node's InternalIP in the SANs (the address type metrics-server dials), so `--kubelet-insecure-tls` can be dropped. After dropping it, watch for `x509` errors in the metrics-server logs and a failing
`v1beta1.metrics.k8s.io` APIService.
