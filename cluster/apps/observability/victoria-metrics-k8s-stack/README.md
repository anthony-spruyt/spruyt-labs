# Victoria Metrics k8s Stack - Cluster Monitoring

## Overview

Victoria Metrics k8s stack provides comprehensive monitoring, alerting, and visualization capabilities for the cluster. This component is critical for observability and operational awareness.

## Prerequisites

- victoria-metrics-operator (dependsOn)
- external-secrets (dependsOn)
- authentik (dependsOn)
- Storage class configured for persistent volume claims

## Troubleshooting

1. **VictoriaMetrics pods not starting**

   - **Symptom**: Pods in CrashLoopBackOff or Pending
   - **Resolution**: Check resource constraints and PVC availability. Verify storage class and chart version compatibility.

2. **No data appearing in metrics**

   - **Symptom**: Queries return empty results
   - **Resolution**: Validate service monitor configurations. Check Cilium network policies for observability namespace. Verify service endpoints are correctly annotated.

## References

- [VictoriaMetrics Official Documentation](https://docs.victoriametrics.com/)
- [Helm Chart Reference](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-metrics-k8s-stack)
