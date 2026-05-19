# Victoria Traces Single - OTLP Trace Storage

## Overview

VictoriaTraces single-node deployment provides OpenTelemetry trace ingestion and storage for the cluster. It backs trace export from Claude agents and other workloads via OTLP HTTP at port 10428. Traces use a 7d retention window (sampled, short-lived compared to logs).

## Prerequisites

- Rook Ceph block storage (`rbd-fast-delete` StorageClass) available
- `ghcr-docker-config` secret in `flux-system` for OCI chart pulls

### OTLP Endpoint

Trace producers should send to:

```text
http://victoria-traces-single-vt-single-server.observability.svc:10428/insert/opentelemetry/v1/traces
```

## Troubleshooting

1. **Traces not appearing**

   - **Symptom**: Producers report 200/202 but query returns empty
   - **Resolution**: Check producer is targeting `/insert/opentelemetry/v1/traces` path; verify CiliumNetworkPolicy allows the source namespace; check container logs for parse errors

2. **Pod evicted or PVC full**

   - **Symptom**: Pod restarts, `df -h` shows full disk in `/storage`
   - **Resolution**: Increase `server.persistentVolume.size` in `values.yaml`, or shorten `server.retentionPeriod`; reconcile via Flux

3. **Network policy blocks ingest**

   - **Symptom**: Producer logs show connection timeout/refused
   - **Resolution**: Confirm source pod has label `managed-by: n8n-claude-code` and runs in `claude-agents-{read,write,sre}`. To allow new namespaces, add an entry to `network-policies.yaml`

## References

- [VictoriaTraces Documentation](https://docs.victoriametrics.com/victoriatraces/)
- [Helm Chart](https://github.com/VictoriaMetrics/helm-charts/tree/master/charts/victoria-traces-single)
- [OTLP HTTP Ingestion](https://docs.victoriametrics.com/victoriatraces/data-ingestion/opentelemetry/)
