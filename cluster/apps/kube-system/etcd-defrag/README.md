# etcd-defrag - Weekly etcd Defragmentation

## Overview

CronJob that performs weekly etcd defragmentation on all control plane nodes using `talosctl`. Defrags followers first, then the leader, with a 10-second stabilization wait between nodes.

## Prerequisites

- Talos machine config with `kubernetesTalosAPIAccess` enabled for `kube-system` (patch: `talos/patches/control-plane/enable-talos-api-access.yaml`)
- Talos ServiceAccount controller generating credentials

### Schedule

Runs every Monday at 2:00 AM AEST (Sunday 16:00 UTC).

## Troubleshooting

### Common Issues

1. **Job fails with permission error**

   - **Symptom**: `rpc error: code = PermissionDenied`
   - **Resolution**: Verify Talos machine config has `kubernetesTalosAPIAccess` enabled. Run `task talos:generate` and `talosctl apply-config` to all control plane nodes.

1. **Secret not found**

   - **Symptom**: Pod fails to start, secret `etcd-defrag-talos-secrets` not found
   - **Resolution**: The Talos ServiceAccount controller creates this secret automatically. Ensure the machine config patch is applied and the controller is running.

1. **Cannot determine leader**

   - **Symptom**: Job logs show "ERROR: Could not determine etcd leader"
   - **Resolution**: Check etcd health with `talosctl etcd status --nodes e2-1,e2-2,e2-3`.

## References

- [Talos etcd Maintenance](https://www.talos.dev/latest/kubernetes-guides/configuration/etcd-maintenance/)
- [Talos API Access from Kubernetes](https://www.talos.dev/latest/kubernetes-guides/configuration/talos-api-access-from-k8s/)
