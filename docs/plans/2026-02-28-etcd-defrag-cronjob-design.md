# etcd Defrag CronJob Design

**Issue:** #575
**Date:** 2026-02-28

## Problem

etcd fragmentation accumulates over time. Manual maintenance showed 68% in-use ratio (122MB -> 83MB after defrag) with 100-375ms slow operations correlated with fragmentation. Automating weekly defrag prevents performance degradation.

## Decision: Talos ServiceAccount Approach

Uses `talosctl etcd defrag` via the Talos API rather than direct etcdctl with hostPath mounts. Requires adding `kubernetesTalosAPIAccess` to Talos machine config.

**Why not direct etcdctl:** Although the cluster already has an etcd hostPath pattern (victoria-metrics-secret-writer), the Talos ServiceAccount approach is cleaner — no hostPath, no hostNetwork, no running as uid 60, and credentials are scoped to `os:operator` rather than full etcd admin.

**Why not GitHub Actions:** Shipping etcd-level credentials to a third-party cloud server is a worse security trade-off than keeping them in-cluster.

## Design

### Files

```
cluster/apps/kube-system/etcd-defrag/
├── ks.yaml                      # Flux Kustomization
└── app/
    ├── kustomization.yaml       # Resource list
    ├── cronjob.yaml             # CronJob + Talos ServiceAccount
    └── rbac.yaml                # K8s ServiceAccount

talos/patches/control-plane/enable-talos-api-access.yaml  # New Talos patch
```

### CronJob

- **Schedule:** `0 16 * * 0` (Monday 2:00 AM AEST)
- **Image:** `ghcr.io/siderolabs/talosctl:<talos-version>`
- **Concurrency:** `Forbid`
- **History:** 3 successful, 3 failed
- **Security:** Non-root, read-only filesystem, all capabilities dropped, seccomp RuntimeDefault

### Script Flow

1. Run `talosctl etcd status` on all control plane nodes
2. Parse output to identify the leader
3. Defrag followers first, then the leader
4. Wait 10 seconds between each node
5. Log etcd status after each defrag for verification

### Credentials

- `talos.dev/v1alpha1 ServiceAccount` generates a Kubernetes Secret
- Mounted at `/var/run/secrets/talos.dev` (talosctl auto-detects)
- Scoped to `os:operator` role (minimum for defrag)

### Talos Config Change

New control plane patch enabling Talos API access from pods:

```yaml
machine:
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        - os:operator
      allowedKubernetesNamespaces:
        - kube-system
```

Requires `talosctl apply` to all control plane nodes after talhelper generation.

### Credential Scoping

Neither Talos nor etcd supports defrag-only credentials:
- **Talos:** `os:operator` is minimum for `EtcdDefragment` RPC. Also grants reboot, shutdown, alarm management. Cannot read files, modify config, or remove etcd members (those need `os:admin`).
- **etcd RBAC:** Operates on key ranges, not API methods. Defrag requires `root` role.

### Not Included

- No alerting/VMRule (add later if needed)
- No threshold-based logic (always defrags unconditionally)
- No custom image builds
