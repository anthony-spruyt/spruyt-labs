# Victoria Metrics Operator - CRD Lifecycle Manager

## Overview

Victoria Metrics Operator manages the lifecycle of VictoriaMetrics custom resources, providing automated provisioning, scaling, and management of VictoriaMetrics instances across the cluster.

## Prerequisites

- CustomResourceDefinitions for VictoriaMetrics installed

## Troubleshooting

1. **Operator pod crash looping**

   - **Symptom**: Operator restarts repeatedly
   - **Resolution**: Check operator logs for permission errors. Verify CRD version compatibility and RBAC configuration.

1. **Custom resources not being processed**

   - **Symptom**: VMSingle/VMAgent CRs stuck in pending state
   - **Resolution**: Verify operator is watching correct namespaces. Check custom resource annotations and labels. Review operator log for reconciliation errors.

## References

- [VictoriaMetrics Operator Documentation](https://docs.victoriametrics.com/operator/)
- [Custom Resource API Reference](https://docs.victoriametrics.com/operator/api/)
- [Helm Chart Values](https://github.com/VictoriaMetrics/helm-charts/blob/master/charts/victoria-metrics-operator/values.yaml)
