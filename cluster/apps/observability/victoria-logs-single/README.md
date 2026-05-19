# Victoria Logs Single - Centralized Log Storage

## Overview

Victoria Logs Single provides centralized log collection and storage for the cluster, enabling comprehensive log analysis and troubleshooting capabilities.

## Prerequisites

- Persistent storage available for log retention

## Troubleshooting

1. **Logs not appearing in Victoria Logs**

   - **Symptom**: Application logs missing from queries
   - **Resolution**: Verify the separate vector deployment is running and collecting logs. Check log collection annotations on application pods. Review Cilium network policies for observability namespace.

2. **High storage usage or retention issues**

   - **Symptom**: PVC nearing capacity
   - **Resolution**: Adjust retention periods in Helm values. Increase PVC size if needed.

## References

- [Victoria Logs Documentation](https://docs.victoriametrics.com/VictoriaLogs/)
- [Helm Chart Reference](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-logs-single)
