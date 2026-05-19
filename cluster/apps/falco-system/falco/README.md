# Falco - Runtime Security Monitoring

## Overview

Falco is a cloud-native runtime security tool that monitors system calls to detect anomalous behavior and potential threats. Deployed as high-priority security observability infrastructure.

Components:

- **Falco** - DaemonSet monitoring syscalls on all nodes via modern_ebpf driver
- **Falcosidekick** - Alert forwarder to VictoriaLogs

## Prerequisites

- Talos Linux with `lockdown=integrity` kernel arg (required for modern_ebpf driver)

## Exception Rules

Workload-specific exceptions are configured in `exceptions-configmap.yaml` to suppress expected behavior:

| Rule                        | Workload           | Namespace        | Reason                       |
| --------------------------- | ------------------ | ---------------- | ---------------------------- |
| Contact K8S API Server      | grafana-sidecar    | observability    | ConfigMap/Secret watching    |
| Contact K8S API Server      | kyverno            | kyverno          | Policy enforcement           |
| Contact K8S API Server      | external-secrets   | external-secrets | Secret synchronization       |
| Contact K8S API Server      | authentik          | authentik-system | Outpost management           |
| Contact K8S API Server      | velero             | velero           | Backup operations            |
| Contact K8S API Server      | kube-state-metrics | observability    | Metrics collection           |
| Contact K8S API Server      | headlamp           | headlamp-system  | K8s dashboard                |
| Contact K8S API Server      | traefik            | traefik          | Ingress controller           |
| Contact K8S API Server      | cloudnative-pg     | cnpg-system      | Operator manages PG clusters |
| Contact K8S API Server      | vector             | observability    | Log collector pod discovery  |
| Contact K8S API Server      | ceph-csi           | rook-ceph        | CSI volume operations        |
| Drop and execute new binary | cilium-cni         | host             | CNI plugin execution         |
| Drop and execute new binary | cilium-sysctlfix   | host             | CNI sysctl fix binary        |
| Drop and execute new binary | coder              | coder-system     | Terraform provider download  |
| Clear Log Activities        | virtiofsd          | host             | Kata VM filesystem daemon    |
| Run shell untrusted         | cloudnative-pg     | \*               | WAL archiver scripts         |

To add new exceptions, edit `exceptions-configmap.yaml` in the app directory. See [Falco Exceptions](https://falco.org/docs/rules/exceptions/) for syntax.

## Troubleshooting

### Common Issues

1. **Driver fails to load**

   - **Symptom**: Falco pods crash with eBPF errors
   - **Resolution**: Verify Talos has `lockdown=integrity` kernel arg (not `lockdown=confidentiality`)

2. **Alerts not appearing in VictoriaLogs**

   - **Symptom**: Falco detecting events but not visible in Grafana
   - **Resolution**: VictoriaLogs requires `/insert` prefix for Loki-compatible endpoint. Verify hostport includes `/insert`: `http://victoria-logs-single-server.observability.svc:9428/insert`

## Future Enhancements

### Falco-talon (Automated Response)

Falco-talon can be enabled to automatically respond to threats:

- Kill malicious containers
- Add network policies
- Label suspicious pods

Currently disabled to focus on detection. Enable in values.yaml when ready: `falco-talon.enabled: true`

Note: Automated responses are ephemeral and don't persist in Git. Flux will recreate resources in clean state after response actions.

## References

- [Falco Documentation](https://falco.org/docs/)
- [Falco Helm Chart](https://github.com/falcosecurity/charts/tree/master/charts/falco)
- [Falcosidekick](https://github.com/falcosecurity/falcosidekick)
