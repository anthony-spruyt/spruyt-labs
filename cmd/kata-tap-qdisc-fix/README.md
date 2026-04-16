# kata-tap-qdisc-fix

DaemonSet that fixes a Cilium ↔ Kata networking regression caused by Linux
kernel ≥6.18 defaulting `tap` devices to the `fq` qdisc whose `horizon_drop`
silently drops Cilium-timestamped reply packets mirrored into the Kata VM
via `tc mirred`.

The daemon watches `/run/netns/` and for every `tap[0-9]+_kata` interface in
any pod netns whose root qdisc is `fq`, replaces it with `pfifo_fast`. Runs
only on nodes labelled `kata.spruyt-labs/ready=true`.

## Reconciliation model

Three input sources, serialised through a single worker goroutine:

1. **Initial sweep** on startup — scan `NETNS_DIR` once.
2. **fsnotify** `IN_CREATE` events — **latency optimisation only**. Netns
   files are created via `mount --bind /proc/<pid>/ns/net`; whether inotify
   fires for bind-mount targets is kernel-version dependent, so this path
   MUST NOT be relied on for correctness.
3. **Periodic full sweep every `SWEEP_INTERVAL` seconds** — the authoritative
   correctness path that catches anything fsnotify missed and also handles
   the common race where Kata creates `tap0_kata` several seconds after the
   netns file appears.

## Build

    go build ./...

## Test

    go test -race ./...

## Run locally (requires CAP_SYS_ADMIN + CAP_NET_ADMIN)

    sudo ./kata-tap-qdisc-fix

## Environment

| Var              | Default      | Meaning                                                |
| ---------------- | ------------ | ------------------------------------------------------ |
| `DRY_RUN`        | `false`      | If `true`, log intended replacements without executing |
| `HEALTH_PORT`    | `8080`       | Port for `/healthz` and `/readyz`                      |
| `METRICS_PORT`   | `9102`       | Port for `/metrics` (Prometheus)                       |
| `NETNS_DIR`      | `/run/netns` | Directory watched for new pod netns                    |
| `LOG_LEVEL`      | `info`       | `debug`, `info`, `warn`, `error`                       |
| `SWEEP_INTERVAL` | `30`         | Seconds between periodic full sweeps                   |

## Canary & Rollback

For initial deploy or risky upgrades, flip the DaemonSet to dry-run mode
first and watch metrics for at least 1h before enforcing.

1. Patch values: set `env.DRY_RUN` to `"true"` in
   `cluster/apps/kube-system/kata-tap-qdisc-fix/app/values.yaml`, commit,
   push. Flux reconciles.
2. Observe for 1h: `kata_tap_qdisc_replacements_total` stays at 0 (enforced
   side-effect disabled), but logs show `"qdisc would replace (dry-run)"`
   lines for every Kata pod that would have been patched. Confirm the
   `netns` paths match real Kata pods.
3. Flip `DRY_RUN` back to `"false"`, commit, push.

Emergency rollback:

    flux -n flux-system suspend hr kata-tap-qdisc-fix
    kubectl -n kube-system scale --replicas=0 ds/kata-tap-qdisc-fix   # not available for DS; use the suspend above
    # Or — revert the Flux Kustomization entirely:
    git revert <cluster-manifest-commit-range>
    git push origin main

Alerting (PromQL):

- `increase(kata_tap_qdisc_replace_failures_total[10m]) > 0` — WARN
- `increase(kata_tap_qdisc_circuit_breaker_opens_total[10m]) > 0` — PAGE
- `increase(kata_tap_qdisc_enqueue_backpressure_total[5m]) > 10` — WARN (transient queue pressure; tune `workCh` size if sustained)
- `increase(kata_tap_qdisc_enqueue_drops_total[5m]) > 0` — PAGE (real saturation; work items were silently lost)
- `increase(kata_tap_qdisc_thread_retired_total[1h]) > 0` — PAGE (a worker OS thread was poisoned by a netns-restore failure)
- `increase(kata_tap_qdisc_worker_respawns_total[1h]) > 0` — PAGE (supervisor replaced a dead worker; correlate with thread-retired counter)

## Root cause reference

See issue anthony-spruyt/spruyt-labs#951 for the packet-trace evidence.
