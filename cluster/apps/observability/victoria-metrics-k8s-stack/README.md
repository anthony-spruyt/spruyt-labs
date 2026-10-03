# Victoria Metrics k8s Stack - Metrics, Alerting and Grafana

## Overview

VMSingle, vmagent, vmalert, Alertmanager and Grafana for the whole cluster. The operator comes from the separate `victoria-metrics-operator` release (`victoria-metrics-operator.enabled: false` here).

## Operations

### Alert routing

`app/alertmanager-config.yaml` routes on `severity`: every non-`Watchdog` alert also goes to the n8n SRE triage webhook, and everything goes to Discord. Webhook URLs and the bearer token are in `app/alertmanager-credentials.sops.yaml`. New rules only need a `severity` label; there is nothing to wire.

`vmalertmanager.spec.disableNamespaceMatcher: true` is required by the inhibit rules. Without it the operator silently scopes every inhibit rule to `namespace="observability"`, and cross-namespace inhibition stops working with no error.

### Adding rules and dashboards

- Rules: a `VMRule` file in `app/vmrules/`, listed in `app/vmrules/kustomization.yaml`.
- LogsQL rules (VictoriaLogs): same, plus group `type: vlogs` and the label `vmalert.spruyt-labs/datasource: victorialogs`. The label routes the rule to the `victoria-logs` VMAlert (`app/vmalert-logs.yaml`) and keeps it out of the chart's vmalert, which would fail parsing LogsQL as MetricsQL. vlogs rules append `_time: <group interval>` themselves, so leave the time filter out of `expr`.
- Dashboards: a JSON file in `app/dashboards/` plus a `configMapGenerator` entry with the `grafana_dashboard: "1"` label in `app/kustomization.yaml`. The Grafana sidecar picks it up; dashboards are not persisted in Grafana.

### Overridden defaults

- `NodeFilesystemSpaceFillingUp` is disabled and replaced by `vmrules/talos-node-filesystem.yaml`, which adds a `deriv() < 0` guard; the default rule's linear prediction misfires on the disk-metric jumps a Talos node restart produces.
- `kube-prometheus-general.rules` is disabled and `RecordingRulesNoData` waits 6h, because idle-cluster recording rules legitimately produce no samples and flapped the alert (#2562).

### Ceph Dashboard integration

The Grafana `Dashboard1` datasource, iframe embedding and the official ceph-mixin dashboards all exist so the Ceph Dashboard can embed Grafana panels. See the [rook-ceph README](../../rook-ceph/README.md#grafana-dashboard-integration) before renaming the datasource or dropping any `grafana-dashboard-ceph-official-*` ConfigMap.

### Grafana SSO

Grafana logs in only through Authentik (`disable_login_form`), with roles mapped from the `Grafana Admins` / `Grafana Editors` groups. The OAuth client comes from Authentik via ExternalSecret and is rotated weekly; see the [authentik README](../../authentik-system/authentik/README.md) (Grafana is the reference example there).

The local `admin` password is ESO-generated into `grafana-admin` by `app/grafana-admin-eso.yaml`; only the dashboard and datasource sidecars use it. Grafana has no persistence and resets it on every start, so to rotate, `kubectl -n observability delete secret,externalsecret grafana-admin` and restart the Grafana deployment.

### etcd scraping

The etcd target selects the `kube-controller-manager` pods to discover control-plane IPs (etcd runs on the same nodes) and scrapes port 2383, the HTTP metrics listener Talos v1.14 split out from gRPC. Client certs come from [victoria-metrics-secret-writer](../victoria-metrics-secret-writer/README.md).
