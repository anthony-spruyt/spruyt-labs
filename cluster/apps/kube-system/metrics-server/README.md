# Metrics Server - Resource Metrics API

## Overview

Serves `metrics.k8s.io` for the VPA recommender's live samples, the descheduler's `LowNodeUtilization` plugin, `kubectl top` and Headlamp.

## Operations

`--kubelet-insecure-tls` was added on the assumption that Talos kubelets serve self-signed certificates. That no longer holds: Talos runs kubelets with `serverTLSBootstrap: true` and kubelet-csr-approver gets the serving certificates signed by the cluster CA, with the node's InternalIP in the SANs (the address type metrics-server dials). The flag is likely removable, but that has not been tested -
if you try, watch for `x509` errors in the metrics-server logs and a failing `v1beta1.metrics.k8s.io` APIService.
