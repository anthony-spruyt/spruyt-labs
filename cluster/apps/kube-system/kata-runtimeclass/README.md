# kata-runtimeclass

## Overview

Registers the `kata` `RuntimeClass` so pods opt into VM-level isolation via Kata Containers. Priority tier: security (#933 Phase-2 of workspace isolation umbrella #921).

## Prerequisites

- `kube-system` namespace (this Kustomization targets it)
- `siderolabs/kata-containers` Talos system extension installed on the worker nodes (declared in `talos/schematics/ms-01.yaml`)
- Nodes labeled `kata.spruyt-labs/ready: "true"` via `machine.nodeLabels` in `talos/patches/worker/08-configure-node-labels.yaml` (not `kubectl label`)

## Operation

### Node scope

All three `ms-01` workers run the Kata-enabled schematic and carry the `kata.spruyt-labs/ready` label. The RuntimeClass's `scheduling.nodeSelector` pins Kata pods to that pool.

### Adopt Kata for a workload

Add to the pod spec:

```yaml
spec:
  runtimeClassName: kata
```

Pod lands on a Kata-ready node automatically via the RuntimeClass selector. No explicit nodeSelector/tolerations needed on the pod.

### Sanity check

```bash
kubectl get runtimeclass kata -o yaml
kubectl get nodes -l kata.spruyt-labs/ready=true
```

### Extend to a node outside the `ms-01` pool

1. Add `siderolabs/kata-containers` to the target node's schematic under `talos/schematics/`
2. Add `kata.spruyt-labs/ready: "true"` to a `machine.nodeLabels` patch that covers the node
3. `task talos:render` → `talosctl upgrade --image=...` (new schematic URL) → `task talos:apply NODE=<node>`

## Troubleshooting

1. **Pod pending, `0/6 nodes available: node(s) didn't match Pod's node affinity`**

   - **Symptom**: Pod with `runtimeClassName: kata` stays Pending.
   - **Resolution**: Verify at least one node has the label: `kubectl get nodes -l kata.spruyt-labs/ready=true`. If empty, the node's Talos config hasn't been applied — run the apply-config task.

2. **`RunContainerError: kata: runtime not installed`**

   - **Symptom**: Pod schedules but fails to start.
   - **Resolution**: Extension not actually loaded. Check `talosctl -n <node> get extensions` for `kata-containers` and `talosctl -n <node> list /etc/cri/conf.d/` for `10-kata-containers.part`.

## References

- [Kata Containers Talos extension](https://github.com/siderolabs/extensions/tree/release-1.12/container-runtime/kata-containers)
- [Kubernetes RuntimeClass](https://kubernetes.io/docs/concepts/containers/runtime-class/)
- Umbrella issue: [#921](https://github.com/anthony-spruyt/spruyt-labs/issues/921)
- Phase-2 issue: [#933](https://github.com/anthony-spruyt/spruyt-labs/issues/933)
