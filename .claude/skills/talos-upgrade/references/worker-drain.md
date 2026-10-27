# Worker Drain Strategy

The Phase 1 PDB survey decides how workers drain in Phase 4. Detail for Step 4.3 (`--drain=false`) and Step 4.3a (recovery from an aborted drain).

## Phase 1: PDB survey

Parallel Group 4 of the Phase 1 checks:

```bash
# Parallel Group 4 - Eviction blockers (determines worker drain strategy)
kubectl get pdb -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,MIN:.spec.minAvailable,MAX:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed' | awk 'NR==1 || $5=="0"'
```

**Pre-flight PDB check (determines worker upgrade strategy — do NOT skip):**

Any PDB with `disruptionsAllowed: 0` will block a drain-based upgrade. Classify what you find:

| PDB pattern                                 | Meaning                                       | Action                        |
| ------------------------------------------- | --------------------------------------------- | ----------------------------- |
| `*-cnpg-cluster-primary`, `minAvailable: 1` | Primary-role PDB, **permanently** unevictable | Use `--drain=false` (Phase 4) |
| `rook-ceph-osd-host-<node>`                 | Rook's own drain protection, normal           | Expected, not a blocker       |
| `rook-ceph-mon-pdb` at `ALLOWED 0`          | A mon is already down                         | STOP, investigate first       |

Every CNPG cluster in this repo sets `enablePDB: false`, so the operator creates no PDB and drains proceed normally. Expect the survey above to return no CNPG entries. If one appears, that setting has been removed from the manifest — the operator's primary-role PDB targets only the primary pod, so `disruptionsAllowed` is `0` regardless of instance count. Do not try to "fix" it during the upgrade (it is a declarative change needing its own PR) — use `--drain=false` and note it as follow-up work.

## Step 4.3: When to add `--drain=false`

**When to add `--drain=false`:** only if the Phase 1 survey found a PDB stuck at `disruptionsAllowed: 0`. `talosctl upgrade` defaults to `--drain=true`, which cordons the node and evicts pods via the eviction API before rebooting; a PDB at `0` blocks that eviction (the CNPG case is explained in the Phase 1 PDB survey above).

The drain then always hits its timeout and the upgrade aborts. This failure mode is worse than useless — it is actively destructive:

1. The drain evicts Ceph mons, OSDs and other pods first
2. Then it times out on the CNPG primary and aborts **before touching the OS**
3. It leaves the node **cordoned**, so the evicted mon and OSD cannot reschedule back (they are pinned to their host's local storage) and sit `Pending`
4. Ceph drops to `HEALTH_WARN` with a mon down, an OSD down and ~33% objects degraded

**Raising `--drain-timeout` does not help.** This is a structural zero, not a slow eviction.

**`--drain=false` is safe here** because Talos has kubelet graceful node shutdown enabled by default. Verify on the live node before relying on it:

```bash
talosctl -n <node-ip> read /etc/kubernetes/kubelet.yaml | grep -i shutdownGracePeriod
# Expect: shutdownGracePeriod: 1m0s / shutdownGracePeriodCriticalPods: 30s
```

Pods still receive SIGTERM and their termination grace period during the reboot sequence, so Postgres shuts down cleanly and Ceph daemons stop gracefully. Only the eviction-API deadlock is bypassed.

**Do NOT manually cordon the node as a substitute.** Cordoning creates the same deadlock: after the reboot the host-pinned mon and OSD pods cannot be scheduled back onto their own node. Leave workers uncordoned throughout.

**Control plane nodes are different** — the default `--drain=true` works fine there, because the CNPG and Ceph workloads that block eviction do not run on control plane nodes.

## Step 4.3a: Recovery if a drain-based upgrade already aborted

If an upgrade aborted during drain and left the node cordoned with Ceph degraded, fix it immediately before anything else:

```bash
kubectl uncordon <hostname>
```

The evicted mon and OSD reschedule onto their home host and Ceph returns to `HEALTH_OK` (typically ~90 seconds). Confirm the node was NOT upgraded before retrying:

```bash
talosctl version --nodes <node-ip> --endpoints <cp-node-ip> --short
```

An abort during drain happens before the OS is touched, so the node stays on the old version and retrying with `--drain=false` is safe.
