# NUT System - UPS Monitoring and Graceful Shutdown

## Overview

Network UPS Tools (NUT) integration for UPS monitoring with automated graceful cluster shutdown during power outages. Protects Ceph storage and CNPG databases from data corruption.

**UPS**: CyberPower CP1500 (USB connection, ~2 min runtime)
**USB Node**: ms-01-1 (worker node with `ups.spruyt-labs.io/connected: "true"` label)

## Components

| Component             | Purpose                                    | Namespace  | Status   |
|-----------------------|--------------------------------------------|------------|----------|
| nut-server            | USB driver + upsd daemon + metrics exporter | nut-system | Active   |
| shutdown-orchestrator | Monitors UPS, triggers graceful shutdown   | nut-system | Disabled |

> **Note**: The shutdown-orchestrator is disabled pending validation. Enable by uncommenting in [kustomization.yaml](kustomization.yaml).

## Prerequisites

- Kubernetes cluster with Flux CD
- Talos node with USB UPS connected and labeled `ups.spruyt-labs.io/connected: "true"`
- Talos udev rules configured for USB UPS access
- rook-ceph with rook-ceph-tools deployment
- CNPG operator installed

## Architecture

```text
USB (ms-01-1) --> NUT Server Pod --> LoadBalancer (:3493) --> Home Assistant
                       |
                       v
                  NUT Exporter --> VictoriaMetrics --> Alerts
                       |
                       v
              Shutdown Orchestrator (monitors OB status)
                       |
         On Battery > 30s: Graceful Shutdown
                       |
    +------------------+------------------+
    v                  v                  v
Hibernate CNPG     Set Ceph Flags    Scale Ceph
    |                  |                  |
    +------------------+------------------+
                       v
            talosctl shutdown (workers, then CP)
```

## Shutdown Sequence

When power is lost for 30+ seconds:

1. **Hibernate CNPG clusters** - Graceful database shutdown preserving PVCs
2. **Set Ceph OSD flags** - noout, nodown, norebalance, nobackfill, norecover
3. **Scale Ceph down** - Operator, OSDs, Managers, Monitors (in order)
4. **Shutdown nodes** - Workers first, then control plane

**Timeline Budget** (~2 min UPS runtime):

| Phase | Duration | Cumulative |
|-------|----------|------------|
| Power loss detection | 0s | 0s |
| Delay timer | 30s | 30s |
| CNPG hibernation | 5s | 35s |
| Ceph flags | 5s | 40s |
| Ceph scaling | 15s | 55s |
| Worker shutdown | 30s | 85s |
| Control plane shutdown | 30s | 115s |

## Operation

### Key Commands

```bash
# Check NUT server status
kubectl get pods -n nut-system -l app.kubernetes.io/name=nut-server
upsc cp1500@<NUT_IP4>:3493

# Check orchestrator status
kubectl get pods -n nut-system -l app.kubernetes.io/name=shutdown-orchestrator
kubectl logs -n nut-system -l app.kubernetes.io/name=shutdown-orchestrator -f

# Check UPS metrics
kubectl exec -n nut-system deploy/nut-server -c upsd -- upsc cp1500

# Force reconcile
flux reconcile kustomization nut-server --with-source
flux reconcile kustomization shutdown-orchestrator --with-source
```

### Dry-Run Testing

The orchestrator starts in dry-run mode (`DRY_RUN=true`). To test:

```bash
# Watch logs during test
kubectl logs -n nut-system -l app.kubernetes.io/name=shutdown-orchestrator -f

# Unplug UPS briefly (<30s) to test detection
# Logs will show power loss detection and countdown

# For full dry-run test, unplug >30s
# Logs will show [DRY-RUN] prefix for all actions without executing
```

To enable live mode after validation:

```bash
# Edit values.yaml: DRY_RUN: "false"
# Or patch directly:
kubectl -n nut-system set env deploy/shutdown-orchestrator DRY_RUN=false
```

### Recovery After Power Outage

After power is restored and nodes boot:

```bash
# Apply recovery job
kubectl apply -f cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml

# Watch recovery progress
kubectl logs -n nut-system job/power-recovery -f

# Clean up job
kubectl delete job -n nut-system power-recovery
```

Recovery script will:
1. Unset Ceph OSD flags
2. Wake hibernated CNPG clusters
3. Verify cluster health

### Manual Recovery

If recovery job fails:

```bash
# Unset Ceph flags
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset nodown
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norebalance
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset nobackfill
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset norecover

# Check Ceph status
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Wake CNPG clusters (remove hibernation annotation)
kubectl annotate cluster <name> -n <namespace> cnpg.io/hibernation-
```

## Troubleshooting

### Common Issues

1. **NUT server can't see UPS**
   - **Symptom**: `upsc` returns "Data stale" or connection errors
   - **Resolution**: Verify USB cable connected to labeled node, check udev rules in Talos config

2. **Orchestrator not detecting power loss**
   - **Symptom**: No logs when UPS unplugged
   - **Resolution**: Check NUT server connectivity: `kubectl exec -n nut-system deploy/shutdown-orchestrator -- upsc cp1500@nut-server-nut:3493 ups.status`

3. **CNPG clusters not hibernating**
   - **Symptom**: `[DRY-RUN]` in logs or annotation errors
   - **Resolution**: Verify RBAC permissions, check DRY_RUN setting

4. **Ceph flags not setting**
   - **Symptom**: "rook-ceph-tools deployment not found"
   - **Resolution**: Ensure rook-ceph-tools is deployed: `kubectl -n rook-ceph get deploy rook-ceph-tools`

5. **Recovery job fails**
   - **Symptom**: Job errors or timeout
   - **Resolution**: Run manual recovery commands, check pod logs

### Validation Commands

```bash
# Verify NUT exporter metrics (scraped via /ups_metrics?ups=cp1500)
curl -s 'http://vmsingle.observability.svc:8428/api/v1/query?query=network_ups_tools_battery_charge{ups="cp1500"}'

# Verify RBAC
kubectl auth can-i create pods/exec -n rook-ceph --as=system:serviceaccount:nut-system:shutdown-orchestrator

# Test Ceph tools access
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
```

## Configuration

### Environment Variables (shutdown-orchestrator)

| Variable | Default | Description |
|----------|---------|-------------|
| NUT_SERVER | nut-server-nut.nut-system.svc.cluster.local | NUT server address |
| NUT_PORT | 3493 | NUT server port |
| UPS_NAME | cp1500 | UPS name in NUT config |
| SHUTDOWN_DELAY | 30 | Seconds on battery before shutdown |
| POLL_INTERVAL | 5 | Seconds between UPS status checks |
| DRY_RUN | true | Set to "false" for live mode |

### Alerts (VMRule)

| Alert | Severity | Condition |
|-------|----------|-----------|
| UPSOnBattery | critical | UPS running on battery (immediate) |
| UPSBatteryLow | critical | Battery < 30% |
| UPSBatteryWarning | warning | Battery < 50% for 1m |
| UPSExporterOffline | warning | Exporter unreachable for 1m |
| UPSHighLoad | warning | Load > 80% for 5m |

## Security

- Orchestrator runs on control plane (tolerates taint) for maximum uptime during shutdown
- RBAC scoped: ClusterRole for nodes/CNPG, Role in rook-ceph for pods/exec and deployments
- talosctl binary verified via SHA256 checksum
- Secrets (NUT users, talosconfig) encrypted with SOPS

## References

- [Network UPS Tools](https://networkupstools.org/)
- [CNPG Hibernation](https://cloudnative-pg.io/documentation/current/declarative_hibernation/)
- [Ceph OSD Flags](https://docs.ceph.com/en/latest/rados/operations/health-checks/)
- [Talos Shutdown](https://www.talos.dev/latest/reference/cli/#talosctl-shutdown)
