# NUT System - UPS Monitoring and Graceful Shutdown

## Overview

Network UPS Tools (NUT) integration for UPS monitoring with automated graceful cluster shutdown during power outages. Protects Ceph storage and CNPG databases from data corruption.

**UPS**: CyberPower CP1500 (USB connection, ~2 min runtime)
**USB Node**: ms-01-1 (worker node with `ups.spruyt-labs.io/connected: "true"` label)

## Components

| Component             | Purpose                                     | Namespace  | Status   |
| --------------------- | ------------------------------------------- | ---------- | -------- |
| nut-server            | USB driver + upsd daemon + metrics exporter | nut-system | Active   |
| shutdown-orchestrator | Monitors UPS, triggers graceful shutdown    | nut-system | Active   |

## Prerequisites

- Kubernetes cluster with Flux CD
- Talos node with USB UPS connected and labeled `ups.spruyt-labs.io/connected: "true"`
- Talos udev rules configured for USB UPS access
- rook-ceph with rook-ceph-tools deployment
- CNPG operator installed
- **Talos API access patch applied**: The `enable-talos-api-access.yaml` patch
  (`talos/patches/control-plane/`) must include `nut-system` in the allowed
  namespaces list. This patch must be applied and Talos configs regenerated
  **before** deploying the shutdown-orchestrator — the Talos ServiceAccount CRD
  auto-provisions the `shutdown-orchestrator-talos-secrets` Kubernetes Secret via
  the Talos API, and the pod will fail to start if this secret does not exist.

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
Hibernate CNPG    Set noout flag    Scale Ceph down
    |                  |                  |
    +------------------+------------------+
                       v
       talosctl shutdown --force (workers, then CP)
```

## Shutdown Sequence

When power is lost for 30+ seconds:

1. **Hibernate CNPG clusters** - Graceful database shutdown preserving PVCs
2. **Set Ceph noout flag** - prevents monitors from marking down OSDs as out
3. **Scale Ceph down** - Operator → OSDs → Monitors → Managers (per Rook
   [node-maintenance.md](https://rook.io/docs/rook/latest/Upgrade/node-maintenance/))
4. **Shutdown nodes** - Workers first (concurrent), then control plane (sequential,
   orchestrator's node last)

**Timeline Budget** (~10-20 min UPS runtime):

| Phase                  | Duration | Cumulative |
| ---------------------- | -------- | ---------- |
| Power loss detection   | 0s       | 0s         |
| Delay timer            | 30s      | 30s        |
| CNPG hibernation       | 60s      | 90s        |
| Ceph noout flag        | 15s      | 105s       |
| Ceph scaling           | 60s      | 165s       |
| Worker shutdown        | 30s      | 195s       |
| Control plane shutdown | 30s      | 225s       |

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

### Testing

The orchestrator supports three modes via `MODE` env var:

- **`monitor`** (default) — preflight checks → auto-recover if needed → UPS polling
- **`test`** — executes real shutdown sequence, skips orchestrator's own CP node,
  waits for nodes to be powered back on, then auto-recovers and verifies health
- **`preflight`** — validates all prerequisites against live cluster, reports
  pass/fail, exits

```bash
# Run preflight checks
kubectl -n nut-system set env deploy/shutdown-orchestrator MODE=preflight

# Watch logs
kubectl logs -n nut-system -l app.kubernetes.io/name=shutdown-orchestrator -f
```

### Recovery After Power Outage

Recovery is automatic — the shutdown-orchestrator pod detects stale state on startup
and recovers before entering the UPS monitoring loop.

Recovery sequence:

1. Wait for Ceph tools pod to become available
2. Scale Ceph back up: Monitors → Managers → OSDs → Operator
3. Unset Ceph noout flag
4. Wake hibernated CNPG clusters
5. Verify cluster health

### Manual Recovery

If automatic recovery fails or the orchestrator pod is not running:

```bash
# Scale Ceph back up (in order)
kubectl -n rook-ceph scale deploy -l app=rook-ceph-mon --replicas=1
kubectl -n rook-ceph scale deploy -l app=rook-ceph-mgr --replicas=1
kubectl -n rook-ceph scale deploy -l app=rook-ceph-osd --replicas=1
kubectl -n rook-ceph scale deploy rook-ceph-operator --replicas=1

# Unset Ceph noout flag
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph osd unset noout

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
   - **Resolution**: Check NUT server connectivity, verify NUT_SERVER and UPS_NAME env vars, check orchestrator pod logs

3. **CNPG clusters not hibernating**
   - **Symptom**: Annotation errors in logs
   - **Resolution**: Verify RBAC permissions, check pod logs for details

4. **Ceph flags not setting**
   - **Symptom**: "rook-ceph-tools deployment not found"
   - **Resolution**: Ensure rook-ceph-tools is deployed: `kubectl -n rook-ceph get deploy rook-ceph-tools`

5. **Automatic recovery fails**
   - **Symptom**: Orchestrator pod logs show recovery errors
   - **Resolution**: Run manual recovery commands (see Manual Recovery section), check pod logs

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

| Variable                    | Default                                     | Description                              |
| --------------------------- | ------------------------------------------- | ---------------------------------------- |
| MODE                        | monitor                                     | Operating mode: monitor, test, preflight |
| NUT_SERVER                  | nut-server-nut.nut-system.svc.cluster.local | NUT server address                       |
| NUT_PORT                    | 3493                                        | NUT server port                          |
| UPS_NAME                    | cp1500                                      | UPS name in NUT config                   |
| SHUTDOWN_DELAY              | 30                                          | Seconds on battery before shutdown       |
| POLL_INTERVAL               | 5                                           | Seconds between UPS status checks        |
| UPS_RUNTIME_BUDGET          | 600                                         | Total UPS runtime budget (seconds)       |
| HEALTH_PORT                 | 8080                                        | Health endpoint port (/healthz)          |
| NODE_NAME                   | (downward API)                              | Kubernetes node name (auto-set)          |
| CNPG_PHASE_TIMEOUT          | 60                                          | CNPG hibernation timeout (seconds)       |
| CEPH_FLAG_PHASE_TIMEOUT     | 15                                          | Ceph noout flag timeout (seconds)        |
| CEPH_SCALE_PHASE_TIMEOUT    | 60                                          | Ceph scale down timeout (seconds)        |
| CEPH_HEALTH_WAIT_TIMEOUT    | 300                                         | Ceph health wait after scale-up (secs)   |
| NODE_SHUTDOWN_PHASE_TIMEOUT | 120                                         | Node shutdown timeout (seconds)          |
| PER_NODE_TIMEOUT            | 15                                          | Per-node shutdown timeout (seconds)      |
| CEPH_WAIT_TOOLS_TIMEOUT     | 600                                         | Ceph tools pod readiness timeout (secs)  |

### Alerts (VMRule)

| Alert              | Severity | Condition                          |
| ------------------ | -------- | ---------------------------------- |
| UPSOnBattery       | critical | UPS running on battery (immediate) |
| UPSBatteryLow      | critical | Battery < 30%                      |
| UPSBatteryWarning  | warning  | Battery < 50% for 1m               |
| UPSExporterOffline | warning  | Exporter unreachable for 1m        |
| UPSHighLoad        | warning  | Load > 80% for 5m                  |

## Security

- Orchestrator runs on control plane (tolerates taint) for maximum uptime during shutdown
- RBAC scoped: ClusterRole for nodes/CNPG, Role in rook-ceph for pods/exec and deployments
- Go binary from GHCR with read-only root filesystem and non-root execution
- Secrets (NUT users, talosconfig) encrypted with SOPS

## References

- [Network UPS Tools](https://networkupstools.org/)
- [CNPG Hibernation](https://cloudnative-pg.io/documentation/current/declarative_hibernation/)
- [Ceph OSD Flags](https://docs.ceph.com/en/latest/rados/operations/health-checks/)
- [Talos Shutdown](https://www.talos.dev/latest/reference/cli/#talosctl-shutdown)
