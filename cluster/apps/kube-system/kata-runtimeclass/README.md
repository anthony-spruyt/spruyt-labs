# kata-runtimeclass - Kata Containers RuntimeClass

## Overview

Registers the `kata` RuntimeClass so pods can opt into VM-level isolation (used by Coder workspaces, #921/#933). The RuntimeClass's `scheduling.nodeSelector` places Kata pods on Kata-ready nodes, so workloads only set `runtimeClassName: kata` - no nodeSelector or tolerations of their own.

## Prerequisites

- `siderolabs/kata-containers` system extension in the node's schematic (`talos/schematics/ms-01.yaml`). The extension ships cloud-hypervisor only, no QEMU.
- Node label `kata.spruyt-labs/ready: "true"` set via `machine.nodeLabels` in `talos/patches/worker/08-configure-node-labels.yaml`, not `kubectl label`.
- [kata-tap-qdisc-fix](../kata-tap-qdisc-fix/README.md) running on the node. Without it Kata pods get an IP but no working network.

## Memory

- Each Kata VM boots with `default_memory` (2048 MiB) on top of the container limits. `overhead.podFixed` adds that, plus 512 MiB headroom, to the pod's requests and cgroup limit, so the scheduler counts it and the host doesn't OOM-kill the VM when the guest fills its RAM. Keep it in step with `default_memory` in the Talos Kata extension. With `sandbox_cgroup_only=false` the VMM and virtiofsd run
  in the unconstrained `/kata_overhead` cgroup, outside this accounting.
- Guest page cache fills the VM's RAM, and cloud-hypervisor has no free page reporting, so the host does not get that memory back until the pod stops. Plan for every Kata pod to hold up to `limit + overhead` of host memory, and expect `kubectl top` (guest view) to show far less. Host `node_memory_Shmem_bytes` shows the real cost (#3322).

## Operations

### Extend Kata to another node

1. Add `siderolabs/kata-containers` to that node's schematic under `talos/schematics/`.
2. Add `kata.spruyt-labs/ready: "true"` to a `machine.nodeLabels` patch covering the node.
3. Upgrade the node to the new schematic image, then `task talos:apply NODE=<node>`.

## Troubleshooting

1. **Pod Pending with `didn't match Pod's node affinity`**

   - **Cause**: No node carries the ready label - usually the Talos config was not applied.
   - **Fix**: `kubectl get nodes -l kata.spruyt-labs/ready=true`; apply the Talos config if empty.

2. **Pod schedules but fails with `kata: runtime not installed`**

   - **Cause**: The label is present but the extension is not loaded (schematic not upgraded).
   - **Fix**: `talosctl -n <node> get extensions` should list `kata-containers`, and `talosctl -n <node> list /etc/cri/conf.d/` should show `10-kata-containers.part`.

## References

- [Kata Containers Talos extension](https://github.com/siderolabs/extensions/tree/main/container-runtime/kata-containers)
