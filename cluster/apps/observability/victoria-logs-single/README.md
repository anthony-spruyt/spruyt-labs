# VictoriaLogs Single - Log Storage

## Overview

Single-node VictoriaLogs instance that stores cluster logs and backs the Grafana `VictoriaLogs` datasource and `mcp-victorialogs`.

## Operations

### Grafana datasource

No workload here mounts `app/victoria-logs-single-secrets.sops.yaml`, but it is not dead. It holds a Grafana datasource provisioning file (`victoria-logs-single-datasource.yaml`) and carries the `grafana_datasource: "1"` label, so the Grafana datasource sidecar in `victoria-metrics-k8s-stack` (`sidecar.datasources.label: grafana_datasource`, `resource: both`) picks it up and provisions the
`VictoriaLogs` datasource. Removing the secret or its label removes the datasource from Grafana.
