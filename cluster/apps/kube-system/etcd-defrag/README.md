# etcd-defrag - Weekly etcd Defragmentation

## Overview

CronJob that performs weekly etcd defragmentation on all control plane nodes using `talosctl`.
Defrags followers first, then the leader, with a 10-second stabilization wait between nodes.

## Prerequisites

- Kubernetes cluster with Flux CD
- Talos machine config with `kubernetesTalosAPIAccess` enabled for `kube-system`
  (patch: `talos/patches/control-plane/enable-talos-api-access.yaml`)
- Talos ServiceAccount controller generating credentials

## Operation

### Key Commands

```bash
# Check CronJob status
kubectl get cronjob etcd-defrag -n kube-system

# Check recent job runs
kubectl get jobs -n kube-system -l batch.kubernetes.io/job-name

# View logs from last run
kubectl logs -n kube-system -l batch.kubernetes.io/controller-uid --tail=100

# Force reconcile
flux reconcile kustomization etcd-defrag --with-source

# Manually trigger a run
kubectl create job --from=cronjob/etcd-defrag etcd-defrag-manual -n kube-system

# Clean up manual job
kubectl delete job etcd-defrag-manual -n kube-system
```

### Schedule

Runs every Monday at 2:00 AM AEST (Sunday 16:00 UTC).

## Troubleshooting

### Common Issues

1. **Job fails with permission error**
   - **Symptom**: `rpc error: code = PermissionDenied`
   - **Resolution**: Verify Talos machine config has `kubernetesTalosAPIAccess` enabled.
     Run `task talos:generate` and `talosctl apply-config` to all control plane nodes.

2. **Secret not found**
   - **Symptom**: Pod fails to start, secret `etcd-defrag-talos-secrets` not found
   - **Resolution**: The Talos ServiceAccount controller creates this secret automatically.
     Ensure the machine config patch is applied and the controller is running.

3. **Cannot determine leader**
   - **Symptom**: Job logs show "ERROR: Could not determine etcd leader"
   - **Resolution**: Check etcd health with `talosctl etcd status --nodes e2-1,e2-2,e2-3`.

## References

- [Talos etcd Maintenance](https://www.talos.dev/latest/kubernetes-guides/configuration/etcd-maintenance/)
- [Talos API Access from Kubernetes](https://www.talos.dev/latest/kubernetes-guides/configuration/talos-api-access-from-k8s/)
