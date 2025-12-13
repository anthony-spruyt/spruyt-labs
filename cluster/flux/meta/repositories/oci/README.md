# OCI Repositories

This directory contains OCIRepository definitions for Helm charts hosted in OCI registries. These repositories are used by Flux to pull chart versions directly from container registries without requiring traditional Helm repositories.

## Contents

- `app-template.yaml` - App template chart from bjw-s labs
- `flux-instance-ocirepo.yaml` - Flux instance operator chart
- `flux-operator-ocirepo.yaml` - Flux operator chart
- `n8n-ocirepo.yaml` - N8N workflow automation chart
- `rook-ceph-cluster-ocirepo.yaml` - Rook Ceph cluster chart
- `rook-ceph-ocirepo.yaml` - Rook Ceph operator chart
- `spegel-ocirepo.yaml` - Spegel registry mirror chart
- `victoria-logs-single-ocirepo.yaml` - Victoria Logs single instance chart
- `victoria-metrics-k8s-stack-ocirepo.yaml` - Victoria Metrics Kubernetes stack chart
- `victoria-metrics-operator-ocirepo.yaml` - Victoria Metrics operator chart

## Management

These repositories are reconciled by Flux and referenced in HelmRelease manifests under `cluster/apps/`. Updates to chart versions should be made through the corresponding HelmRelease `spec.chart.spec.version` fields.
