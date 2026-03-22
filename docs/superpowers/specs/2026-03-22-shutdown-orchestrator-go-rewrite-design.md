# Shutdown Orchestrator Go Rewrite

**Issue:** [#719](https://github.com/anthony-spruyt/spruyt-labs/issues/719)
**Date:** 2026-03-22
**Status:** Draft

## Problem

The shutdown-orchestrator scripts (`shutdown.sh`, `recovery.sh`) automate the most destructive action in the cluster: shutting down every node during a power outage. They have never been validated end-to-end. Specific problems:

- **DRY_RUN validates nothing** — wraps commands in `run()` that returns 0 without checking prerequisites, command correctness, or sequencing
- **`|| true` masks all failures** — every step swallows errors silently, both in dry-run and real mode
- **Recovery is manual** — requires `kubectl apply` from outside the cluster, but DNS (Technitium) depends on Ceph PVCs, creating a chicken-and-egg problem after power restore
- **No timeouts** — `talosctl shutdown` without `--force` can hang indefinitely on stuck drains, burning the UPS window
- **No testability** — the only way to test is a real power outage

## Constraints

- **UPS budget**: CyberPower CP1500, ~10-20 minutes runtime
- **DNS dependency**: Technitium runs in-cluster with a Ceph PVC — DNS is unavailable until Ceph recovers after boot
- **No remote management**: No IPMI/BMC — physical access required to power on nodes after shutdown
- **Talos OS**: Immutable, no SSH — node operations via `talosctl` only
- **Node shutdown behavior**: `talosctl shutdown` without `--force` cordons and drains, which can hang on PDB-protected workloads. `--force` skips drain entirely. Cordon state persists in etcd, so `--force` is required to avoid nodes booting back as unschedulable.

## Design

### Go Binary

Replace both shell scripts with a single Go binary. Three operating modes:

| Mode | Trigger | Behavior |
| ---- | ------- | -------- |
| **monitor** | Default (pod starts) | Preflight checks → auto-recover if needed → UPS polling loop → shutdown on power loss |
| **test** | `--mode=test` or `MODE=test` env | Execute real shutdown sequence, skip last CP node, wait for nodes to rejoin, auto-recover, verify health |
| **preflight** | `--mode=preflight` or `MODE=preflight` env | Validate all prerequisites against live cluster, report pass/fail, exit |

### Monitor Mode Startup Sequence

```text
Pod starts
  → Run preflight checks (fail = don't start monitoring)
  → Detect if recovery is needed (Ceph flags set? CNPG hibernated?)
  → If recovery needed: run recovery sequence
  → Enter UPS polling loop
```

This eliminates the manual recovery job. After a power outage, nodes boot, Kubernetes schedules the orchestrator pod, and it automatically recovers the cluster before resuming UPS monitoring.

### Shutdown Sequence

Identical for both real and test mode (except test skips last CP):

1. **CNPG hibernation** — annotate all CNPG clusters with `cnpg.io/hibernation=on`
2. **Ceph flag setting** — set `noout`, `nodown`, `norebalance`, `nobackfill`, `norecover` via Ceph tools pod
3. **Ceph scale-down** — scale operator → OSDs → managers → monitors to 0 replicas
4. **Node shutdown** — workers concurrently (goroutines with WaitGroup, phase timeout covers all), then control plane sequentially (`--force --wait=false`). The orchestrator's own node (discovered via `NODE_NAME` downward API env var) is always last — in real mode it shuts itself down as the final action, in test mode it skips itself entirely.

### Test Mode

Executes the real shutdown sequence against the real cluster. The only difference from a real power outage:

- Discovers its own node at runtime via Kubernetes downward API (`NODE_NAME` env var injected by the pod spec) and excludes that node from shutdown — regardless of which CP node the scheduler placed it on
- After shutdown, waits for nodes to be powered back on (user does this physically)
- Once nodes rejoin, runs the recovery sequence automatically
- Verifies cluster health and reports results

This validates the exact code paths that would execute during a real outage, including node shutdown behavior (which has been observed to not work as expected with `--force --wait`).

### Recovery Sequence

Runs automatically on pod startup (monitor mode) or after test mode shutdown:

1. **Wait for Ceph tools pod** — retry with exponential backoff (1s, 2s, 4s, ..., max 30s interval) up to 10 minutes. Ceph tools pod depends on monitors/OSDs which depend on nodes being ready with storage. If tools pod never becomes available, log error and continue to CNPG recovery (flags can be unset manually later).
2. **Unset Ceph flags** — remove `noout`, `nodown`, `norebalance`, `nobackfill`, `norecover`
3. **Wake CNPG clusters** — remove `cnpg.io/hibernation` annotation from all hibernated clusters
4. **Verify health** — poll node readiness, Ceph health status, CNPG cluster status

5. **Scale Ceph back up** — reverse of scale-down: monitors → managers → OSDs → operator (each back to 1 replica). Flux does not reliably restore Ceph replica counts after a manual scale-down, so this must be done explicitly.

### Preflight Mode

Validates all prerequisites against the live cluster. Replaces DRY_RUN with checks that actually verify the shutdown path would work:

| Check | What it validates |
| ----- | ----------------- |
| Kubernetes API reachable | client-go can connect |
| CNPG CRD exists | `clusters.postgresql.cnpg.io` registered |
| CNPG clusters listable | RBAC allows list across namespaces |
| Ceph tools pod exists | `deploy/rook-ceph-tools` in `rook-ceph` namespace |
| Ceph tools pod exec works | Can exec a no-op command |
| Ceph deployments listable | Can list OSD/mgr/mon deployments by label |
| Talos API reachable | Can connect to each node IP |
| Node IPs configured | All 6 node IP env vars are set and non-empty |
| UPS reachable | Go NUT client can query UPS status via NUT protocol |

Exit code 0 = all checks pass. Non-zero = report which checks failed.

### Timeout Model

Every operation has a bounded execution time. Timeouts are configured via env vars with sensible defaults.

```text
UPS runtime budget (configurable, default 600s)
  └─ Shutdown delay (configurable, default 30s)
  └─ Remaining = deadline for shutdown sequence
       ├─ CNPG hibernation:  phase timeout (default 60s)
       │    └─ per-cluster:  command timeout (default 10s)
       ├─ Ceph flags:        phase timeout (default 30s)
       │    └─ per-flag:     command timeout (default 5s)
       ├─ Ceph scale-down:   phase timeout (default 60s)
       │    └─ per-deploy:   command timeout (default 10s)
       └─ Node shutdown:     phase timeout (default 120s)
            └─ per-node:     command timeout (default 15s)
```

If a phase exceeds its timeout, log the failure and proceed to the next phase. The overall deadline is enforced: if approaching the budget limit, skip remaining phases and go directly to node shutdown — getting nodes down cleanly is the priority over Ceph/CNPG niceties.

All operations use Go's `context.WithTimeout` for cancellation propagation.

### Error Handling

Each failure has a defined severity and action. No blanket `|| true`.

| Phase | Failure | Severity | Action |
| ----- | ------- | -------- | ------ |
| CNPG hibernate | CRD not installed | **info** | Skip — no databases to protect |
| CNPG hibernate | Can list but can't annotate | **error** | Log, continue — databases survive unclean shutdown |
| Ceph flags | Tools pod missing | **warning** | Continue — Ceph self-heals, just slower recovery |
| Ceph flags | Individual flag fails | **warning** | Continue with remaining flags |
| Ceph scale-down | Can't scale operator | **warning** | Continue — Flux reconciles on recovery anyway |
| Ceph scale-down | Can't scale OSDs/mons | **warning** | Continue — node shutdown kills them anyway |
| Node shutdown | Single node timeout | **error** | Move to next node — can't let one node burn the window |
| Node shutdown | talosctl auth failure | **fatal** | Abort node shutdown phase — fundamentally broken |
| Preflight | Any check fails | **fail** | Report all failures, don't start monitoring |

**Key principle:** CNPG and Ceph phases are best-effort optimization — they make recovery cleaner but the cluster survives without them. Node shutdown is the actual goal.

**Why `--force` on node shutdown:** `--force` skips cordon and drain, meaning pods
receive SIGKILL without graceful termination. This is acceptable because data-safety
steps (CNPG hibernation, Ceph flags) execute before node shutdown. If those phases
fail, the cluster still survives — it's the same outcome as a hard power loss, which
is what would happen if we let `talosctl shutdown` hang on a drain and burn the UPS
window. The `--force` flag also prevents nodes from booting back as unschedulable
(cordon state persists in etcd).

## Go Project Structure

```text
cmd/shutdown-orchestrator/
├── main.go              # CLI flags, mode selection, entrypoint
├── config.go            # Configuration from env vars / flags
├── orchestrator.go      # Core sequence logic (shutdown, recover, test)
├── monitor.go           # UPS polling loop
├── preflight.go         # Prerequisite validation
├── phases/
│   ├── cnpg.go          # Hibernate / wake CNPG clusters
│   ├── ceph.go          # Flags, scale down / up
│   └── nodes.go         # Shutdown via talosctl
├── clients/
│   ├── kubectl.go       # Interface + real implementation
│   ├── talosctl.go      # Interface + real implementation
│   └── ups.go           # Interface + real implementation
└── clients/mock/
    ├── kubectl.go       # Mock for unit tests
    ├── talosctl.go
    └── ups.go
```

### Key Interfaces

```go
type KubeClient interface {
    // CNPG operations
    GetCNPGClusters(ctx context.Context) ([]CNPGCluster, error)
    SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error

    // Ceph operations — ExecInDeployment resolves deploy to pod internally
    DeploymentExists(ctx context.Context, ns, name string) (bool, error)
    ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error)
    ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error
    ListDeploymentNames(ctx context.Context, ns string, labelSelector string) ([]string, error)

    // Node operations
    GetNodes(ctx context.Context) ([]Node, error)

    // Recovery detection
    GetCephFlags(ctx context.Context) ([]string, error) // execs "ceph osd dump" in tools pod, parses flags
}

type TalosClient interface {
    Shutdown(ctx context.Context, nodeIP string, force bool) error
}

type UPSClient interface {
    GetStatus(ctx context.Context) (string, error)
}
```

**Notes:**
- `SetCNPGHibernation(hibernate=true)` sets the annotation, `SetCNPGHibernation(hibernate=false)` removes it. Single method handles both shutdown and recovery.
- `ExecInDeployment` takes a deploy name but internally resolves to a pod (list pods by deployment label selector, pick first ready pod, exec). This matches the `kubectl exec deploy/` convenience pattern.
- `GetCephFlags` wraps exec + parsing for recovery detection — returns currently set flags so the orchestrator can determine if recovery is needed.

All methods accept `context.Context` for timeout propagation and cancellation.

### Client Implementations

- **KubectlClient**: Uses [client-go](https://github.com/kubernetes/client-go) for Kubernetes API calls. No `kubectl` binary dependency.
- **TalosClient**: Uses the [Talos gRPC API client](https://github.com/siderolabs/talos/tree/main/pkg/machinery/client). No `talosctl` binary dependency.
- **UPSClient**: Uses a Go NUT client library. The NUT protocol is simple (TCP, line-based commands like `GET VAR <ups> ups.status`). If no mature library is available, a minimal client can be implemented directly — it's ~50 lines to query a single variable over TCP. No shell or `upsc` binary dependency.

### Unit Tests

Mock clients verify:

- **Ordering**: CNPG → Ceph flags → Ceph scale → nodes, in that exact order
- **Timeout behavior**: Mock that hangs → verify phase is abandoned within timeout
- **Error propagation**: Mock that fails → verify correct severity handling (continue vs. abort)
- **Test mode**: Verify last CP node is skipped
- **Recovery detection**: Verify startup correctly identifies when recovery is needed (flags set, clusters hibernated)
- **Preflight**: Each check independently testable with mocked success/failure

## Container Image

### Current (problems)

- `bitnami/kubectl:latest` — unpinned, large, unnecessary
- Init container installs `talosctl` and `upsc` at runtime — slow startup, network dependency, `apt-get` in production
- Runs as root (UID 0)

### New

- **Multi-stage Dockerfile**:
  1. Build stage: `golang:1.24` — compile static binary
  2. Final stage: `gcr.io/distroless/static` — just the binary (~10MB total)
- **No external binary dependencies** — client-go and Talos gRPC client replace `kubectl` and `talosctl`
- **No init container** — everything is in the single binary
- **Non-root** (UID 65534)
- **Read-only root filesystem**
- **CI**: GitHub Actions builds and pushes to GHCR on PR merge

### Deployment Changes

| Current | New |
| ------- | --- |
| `bitnami/kubectl:latest` | `ghcr.io/anthony-spruyt/shutdown-orchestrator:<tag>` |
| Init container + emptyDir for tools | None |
| `shutdown-script-configmap.yaml` | Removed — logic in binary |
| `recovery-script-configmap.yaml` | Removed — logic in binary |
| `recovery-job.yaml` | Removed — auto-recovery in monitor mode |
| `TALOSCONFIG` env + secret mount | Keep secret mount — Go binary parses talosconfig file to extract endpoint/CA/client cert for gRPC client |
| `DRY_RUN` env var | `MODE` env var (`monitor`/`test`/`preflight`) |
| Root (UID 0) | Non-root (UID 65534) |

### Configuration

All configuration via environment variables (compatible with Flux substitution):

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `MODE` | `monitor` | Operating mode: `monitor`, `test`, `preflight` |
| `NUT_SERVER` | `nut-server-nut.nut-system.svc.cluster.local` | NUT server address |
| `NUT_PORT` | `3493` | NUT server port |
| `UPS_NAME` | `cp1500` | UPS name in NUT config |
| `SHUTDOWN_DELAY` | `30` | Seconds on battery before shutdown |
| `POLL_INTERVAL` | `5` | Seconds between UPS status checks |
| `UPS_RUNTIME_BUDGET` | `600` | Total UPS runtime in seconds (for deadline calculation) |
| `CNPG_PHASE_TIMEOUT` | `60` | CNPG phase timeout in seconds |
| `CEPH_FLAGS_PHASE_TIMEOUT` | `30` | Ceph flags phase timeout in seconds |
| `CEPH_SCALE_PHASE_TIMEOUT` | `60` | Ceph scale-down phase timeout in seconds |
| `NODE_SHUTDOWN_PHASE_TIMEOUT` | `120` | Node shutdown phase timeout in seconds |
| `HEALTH_PORT` | `8080` | HTTP health endpoint port |
| `NODE_NAME` | — | Injected via downward API (`fieldRef: spec.nodeName`). Used in test mode to identify own node. |
| `MS_01_1_IP4` | — | Worker node 1 IP (Flux substitution) |
| `MS_01_2_IP4` | — | Worker node 2 IP (Flux substitution) |
| `MS_01_3_IP4` | — | Worker node 3 IP (Flux substitution) |
| `E2_1_IP4` | — | Control plane node 1 IP (Flux substitution) |
| `E2_2_IP4` | — | Control plane node 2 IP (Flux substitution) |
| `E2_3_IP4` | — | Control plane node 3 IP (Flux substitution) |

### Health Probes

The current deployment uses `pgrep -f shutdown.sh` which is not available in a distroless container. The Go binary exposes an HTTP health endpoint:

- **`/healthz`** on port 8080 (configurable via `HEALTH_PORT` env var)
- Returns 200 when the binary is running and the UPS polling loop is active
- Returns 503 during shutdown sequence (prevents Kubernetes from restarting during shutdown)
- Liveness and readiness probes both use this endpoint

## RBAC

Existing RBAC (`rbac.yaml`) is sufficient. The Go binary makes the same API calls as the shell scripts. No additional permissions needed.

## Out of Scope

- **Talos ServiceAccount CRD migration** (#578) — separate issue, can be done before or after this rewrite
- **CI integration for tests** — future enhancement once the binary and tests exist
- **Alerting/metrics** — the binary logs structured output; Prometheus metrics could be added later
- **Multi-UPS support** — single UPS is the current hardware reality
