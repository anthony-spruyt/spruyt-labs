# Intel Hybrid Architecture (P-cores and E-cores)

Configuration and tuning for Intel 12th+ Gen hybrid CPUs in the MS-01 worker nodes.

## Overview

The MS-01 worker nodes use Intel i5-12600H processors with hybrid architecture:

| Core Type | CPU IDs | Physical Cores | Threads | Purpose |
|-----------|---------|----------------|---------|---------|
| P-cores (Performance) | 0-7 | 4 | 8 (HT enabled) | Low-latency, high single-thread perf |
| E-cores (Efficiency) | 8-15 | 8 | 8 (no HT) | Throughput, background tasks |

### When Each Core Type Is Used

- **P-cores**: Interrupt handling, latency-sensitive workloads, single-threaded tasks
- **E-cores**: Batch processing, background I/O, throughput workloads (Ceph OSDs)

## Current Configuration

### IRQ Balance

**File:** `cluster/apps/irq-balance/irq-balance-ms-01/app/values.yaml`

Prevents hardware interrupts from being scheduled on E-cores:

```yaml
IRQBALANCE_BANNED_CPULIST: 8-15
```

This ensures network, USB, and other IRQs are handled by P-cores for lower latency.

### Intel HWP Dynamic Boost

**File:** `talos/talconfig.yaml`

Enables Hardware P-state dynamic boosting for P-core turbo:

```yaml
machine:
  sysfs:
    devices.system.cpu.intel_pstate.hwp_dynamic_boost: 1
```

## IRQ Handling Details

### What irqbalance Controls

irqbalance can move these interrupts to P-cores:

- Network interfaces (eth0, eth1-TxRx queues)
- USB controllers (xhci_hcd)
- Thunderbolt data queues (high-throughput)
- Generic PCI devices

> **Note**: Some low-frequency control interrupts (PCIe hotplug, thunderbolt control) may still appear on E-cores. These handle minimal traffic and don't impact performance.

### What irqbalance Cannot Control

NVMe "managed interrupts" are pinned by the kernel at boot:

| NVMe Queue | CPU Affinity | Core Type |
|------------|--------------|-----------|
| nvme1q1 | 0-1 | P-core |
| nvme1q2 | 2-3 | P-core |
| nvme1q3 | 4-5 | P-core |
| nvme1q4 | 6-7 | P-core |
| nvme1q5 | 8-9 | E-core |
| nvme1q6 | 10-11 | E-core |
| nvme1q7 | 12-13 | E-core |
| nvme1q8 | 14-15 | E-core |

> **Note**: IRQ numbers are assigned at boot and may vary. Use the verification commands below to check actual values on your nodes.

**This is by design**: NVMe creates per-CPU queues for cache locality. When a thread on CPU 10 does I/O, the completion interrupt stays on CPU 10, avoiding cache bouncing.

### Why NVMe E-core Queues Are OK

For throughput workloads like Ceph:

1. Each CPU has its own queue - no contention
2. Completions on same CPU - cache locality preserved
3. All 16 CPUs can do parallel I/O - maximum throughput

Limiting queues to P-cores only (`nvme.num_queues=8`) would:

- Force 16 CPUs to share 8 queues
- Increase lock contention
- Reduce Ceph OSD performance

## Guaranteed P-Core Execution

For workloads requiring guaranteed P-core execution (ultra-low latency, real-time):

### Option 1: Kubernetes CPU Manager (Recommended)

Add to kubelet configuration in `talos/patches/global/configure-kubelet.yaml`:

```yaml
machine:
  kubelet:
    extraConfig:
      cpuManagerPolicy: static
      cpuManagerReconcilePeriod: 10s
      reservedSystemCPUs: "0-1"  # Reserve 2 CPUs for system
```

Then request integer CPUs in pod spec:

```yaml
resources:
  requests:
    cpu: "2"    # Integer = dedicated cores
  limits:
    cpu: "2"    # Must match for static policy
```

The kubelet will pin this pod to specific P-cores (from available pool after reserved).

### Option 2: Node Affinity + Taints

Create a node label for P-core-only nodes or use pod topology hints.

### Option 3: Kernel Parameters (Not Recommended)

```text
isolcpus=8-15
```

Prevents any scheduling on E-cores. Wastes 50% of CPU capacity.

## Verification Commands

### Check CPU Topology

```bash
talosctl -n <node-ip> read /proc/cpuinfo | grep -E "^(processor|core id|model name)"
```

P-cores have core IDs 0, 4, 8, 12. E-cores have sequential IDs 16-23.

### Check IRQ Distribution

```bash
talosctl -n <node-ip> read /proc/interrupts | head -20
```

Columns CPU0-CPU7 should show interrupt activity. CPU8-CPU15 should be minimal (except for their own NVMe queues).

### Check IRQ Affinity

```bash
talosctl -n <node-ip> read /proc/irq/<irq-num>/smp_affinity_list
```

Should show P-core CPUs (0-7) for network/USB IRQs.

### Verify irqbalance Running

```bash
kubectl get pods -n irq-balance -o wide
```

All irq-balance-ms-01 pods should be Running.

## Related Documentation

- [Workload Classification](workload-classification.md) - Priority classes
- [cluster/apps/irq-balance/](../cluster/apps/irq-balance/) - IRQ balance deployments
- [talos/talconfig.yaml](../talos/talconfig.yaml) - Node configuration
