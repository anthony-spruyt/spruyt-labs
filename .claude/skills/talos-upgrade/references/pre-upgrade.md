# Phase 1: Pre-Upgrade Checks

Commands for the Phase 1 checks. The checklist and the BLOCK rule are in the skill. Parallel Group 4, the PDB survey, is in [worker-drain.md](worker-drain.md); the pre-flight drift check is in [drift-check.md](drift-check.md).

## Parallel Groups 1 to 3

**Run ALL checks. BLOCK if any fail.**

```bash
# Parallel Group 1 - Cluster health
# talosctl health takes a single node; it discovers the cluster from there
talosctl health -n <any-cp-node-ip>
kubectl get nodes -o wide

# Parallel Group 2 - etcd and storage
# CP nodes only; workers answer etcd calls with "Unimplemented"
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Parallel Group 3 - GitOps
flux get kustomizations -A
flux get helmreleases -A
```

## Installer images

**Verify installer images before starting**, for BOTH schematics ([Schematic Discovery](discovery.md#schematic-discovery)). The Factory builds SecureBoot assets lazily, so the first request for a new version can take 60+ seconds and may appear to hang. Retry once before concluding the image is missing:

```bash
curl -sS --max-time 60 -o /dev/null -w "%{http_code}\n" \
  "https://factory.talos.dev/v2/metal-installer-secureboot/<schematic>/manifests/<target-version>"
# Expect 200. A timeout on first call usually means the image is still being built - retry.
```
