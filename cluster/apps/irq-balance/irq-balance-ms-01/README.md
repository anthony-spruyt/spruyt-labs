# irq-balance-ms-01 - IRQ and RSS Tuning for MS-01 Workers

## Overview

Keeps hardware interrupts off the E-cores and spreads NIC receive queues across P-cores on the MS-01 workers. Added after one P-core pair took nearly all network interrupts on ms-01-2 and thermally throttled ([#236](https://github.com/anthony-spruyt/spruyt-labs/issues/236)). The e2 control-plane variant is plain irqbalance with no tuning.

## Operations

- `IRQBALANCE_BANNED_CPULIST: 8-15` bans the E-cores. See [`docs/intel-hybrid-architecture.md`](../../../../docs/intel-hybrid-architecture.md) for the core layout and which interrupts (NVMe queues) irqbalance cannot move.
- The `tune-rss` init container runs `ethtool -X enp89s0 equal 4` on the host network namespace. `enp89s0` is the kernel alternate name; Talos lists the same NIC as `eth1`, and its interrupts show as `eth1-TxRx-*` in `/proc/interrupts`. The init container logs success or failure but never fails the pod, so a silently unsupported NIC looks healthy.
- RSS changes only affect new flows; existing connections stay on their original queue until they reconnect.

### Checking the result

```bash
# Interrupt spread per queue (should be balanced across CPUs 0-7)
talosctl -n ms-01-2 read /proc/interrupts | grep eth1-TxRx
```

For the RSS indirection table itself, `ethtool -x enp89s0` needs a privileged host-network pod on the node (`task dev-env:priv-pod-ms-2` gives a shell; install `ethtool` in it).

## References

- [Linux RSS and RPS scaling](https://docs.kernel.org/networking/scaling.html)
