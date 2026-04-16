# kata-tap-qdisc-fix

DaemonSet that fixes a Cilium ↔ Kata networking regression caused by Linux
kernel ≥6.18 defaulting `tap` devices to the `fq` qdisc whose `horizon_drop`
silently drops Cilium-timestamped reply packets mirrored into the Kata VM
via `tc mirred`.

The daemon walks `/proc/*/ns/net`, deduplicates by netns inode, and for every
`tap[0-9]+_kata` interface in any container netns whose root qdisc is `fq`,
replaces it with `pfifo_fast`. This approach finds taps that live in
cloud-hypervisor's orphan netns, which `/run/netns` never surfaces. Runs only
on nodes labelled `kata.spruyt-labs/ready=true`.

## Reconciliation model

Single proc-sweep loop — no fsnotify, no retry state:

1. **Initial sweep** on startup — walk `/proc/*/ns/net` once.
2. **Periodic full sweep every `SWEEP_INTERVAL` seconds** — the authoritative
   correctness path. Transient errors (process exited mid-sweep, netns
   disappears) are logged at debug level and silently retried on the next sweep.

Deduplication is by netns inode, so shared-netns pods are visited exactly once
regardless of how many `/proc/<pid>/ns/net` symlinks point to the same netns.
The host netns (inode of `/proc/1/ns/net`) is always excluded.

## Build

```bash
go build ./...
```

## Test

```bash
go test -race ./...
```

## Run locally (requires CAP_SYS_ADMIN + CAP_NET_ADMIN)

```bash
sudo ./kata-tap-qdisc-fix
```

## Environment

| Var              | Default      | Meaning                                                |
| ---------------- | ------------ | ------------------------------------------------------ |
| `DRY_RUN`        | `false`      | If `true`, log intended replacements without executing |
| `HEALTH_PORT`    | `8080`       | Port for `/healthz` and `/readyz`                      |
| `METRICS_PORT`   | `9102`       | Port for `/metrics` (Prometheus)                       |
| `LOG_LEVEL`      | `info`       | `debug`, `info`, `warn`, `error`                       |
| `SWEEP_INTERVAL` | `30`         | Seconds between periodic full sweeps                   |

## Canary & Rollback

For initial deploy or risky upgrades, flip the DaemonSet to dry-run mode
first and watch metrics for at least 1h before enforcing.

1. Patch values: set `env.DRY_RUN` to `"true"` in
   `cluster/apps/kube-system/kata-tap-qdisc-fix/app/values.yaml`, commit,
   push. Flux reconciles.
2. Observe: `kata_tap_qdisc_replacements_total` stays at 0 (enforced
   side-effect disabled), but logs show `"qdisc would replace (dry-run)"`
   lines for every Kata pod that would have been patched. Confirm the
   `path` log fields match real Kata pods.
3. Flip `DRY_RUN` back to `"false"`, commit, push.

Emergency rollback:

```bash
flux -n flux-system suspend hr kata-tap-qdisc-fix
# Or — revert the Flux Kustomization entirely:
git revert <cluster-manifest-commit-range>
git push origin main
```

Alerting (PromQL):

- `increase(kata_tap_qdisc_replace_failures_total[10m]) > 0` — WARN

## Root cause reference

See issue anthony-spruyt/spruyt-labs#951 for the packet-trace evidence and
anthony-spruyt/spruyt-labs#959 for the proc-enumeration spike results.
