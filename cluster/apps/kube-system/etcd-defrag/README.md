# etcd-defrag - Weekly etcd Defragmentation

## Overview

Weekly CronJob that defragments etcd on each control-plane node through the Talos API, followers first and the leader last, so the cluster never loses quorum and the leader only stalls once.

## Prerequisites

- `kubernetesTalosAPIAccess` enabled for `kube-system` with the `os:operator` role in `talos/patches/control-plane/08-enable-talos-api-access.yaml`.
- Talos then materialises the `talos.dev/v1alpha1` `ServiceAccount` in `app/serviceaccount.yaml` as the `etcd-defrag-talos-secrets` Secret the job mounts. Without the patch the Secret never appears and the pod stays in `ContainerCreating`.

## Operations

- The node list is hard-coded (`NODES` env in `app/cronjob.yaml`); update it if control-plane nodes are renamed or added.
- The job downloads `talosctl` at runtime. Its version is Renovate-tracked from the `siderolabs/talos` releases, so it should match the cluster after a Talos upgrade.
- Leader detection parses `talosctl etcd status` columns with `awk`. A Talos release that changes that table layout breaks it with `Could not determine etcd leader`.

## Troubleshooting

1. **`rpc error: code = PermissionDenied`**
   - **Cause**: The Talos API access patch is missing on a control-plane node.
   - **Fix**: `task talos:apply NODE='e2-.*'`.

## References

- [Talos API access from Kubernetes](https://www.talos.dev/latest/advanced/talos-api-access-from-k8s/)
- [Talos etcd maintenance](https://www.talos.dev/latest/advanced/etcd-maintenance/)
