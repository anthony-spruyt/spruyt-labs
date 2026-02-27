---
name: kubernetes-upgrade
description: Use when the user asks to "upgrade Kubernetes", "upgrade k8s", "update Kubernetes version", "bump Kubernetes version", mentions a target version like "upgrade to 1.35.1", or when Renovate updates kubernetesVersion in talconfig.yaml. Not for Talos OS upgrades (use talos-upgrade agent).
argument-hint: <target-version>
---

# Kubernetes Upgrade

Orchestrate safe Kubernetes version upgrades on Talos Linux. Primary value: comprehensive pre-flight safety before `talosctl upgrade-k8s`.

## Quick Reference

| Item | Value |
|------|-------|
| Upgrade command | `talosctl upgrade-k8s -n <cp-node> --to v<version>` |
| Config file | `talos/talconfig.yaml` (`kubernetesVersion` field) |
| Node topology | 3 CP (e2-1/2/3), 3 workers (ms-01-1/2/3) |
| Talos OS agent | `talos-upgrade` (different from this skill) |

## Workflow

### Phase 0: Input Parsing

- Parse target version from user message; prompt if missing
- Read current version from `talos/talconfig.yaml` (`kubernetesVersion`)
- Classify: **minor** (1.34→1.35, higher risk) or **patch** (1.35.0→1.35.1)

### Phase 1: Breaking Changes Research

Consult `references/breaking-changes-lookup.md` for procedures.

**HARD GATE:** Present findings. Wait for user acknowledgment. If removed APIs match cluster resources, recommend aborting.

### Phase 2: Cluster API Compatibility Scan

Consult `references/api-deprecation-scanning.md` for procedures.

**HARD GATE:** If removed APIs are in active use, BLOCK. List resources requiring migration.

### Phase 3: Talos Compatibility Check

1. Read Talos version from `talos/talconfig.yaml` (`talosVersion`)
2. Query Context7: `query-docs(libraryId: "/siderolabs/talos", query: "supported kubernetes versions for Talos v<current>")`

**HARD GATE:** If incompatible, BLOCK. Recommend `talos-upgrade` agent first.

### Phase 4: Cluster Health Gate

Discover CP node IPs dynamically:
```bash
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
```

| Check | Command | Pass Criteria |
|-------|---------|---------------|
| Nodes | `kubectl get nodes -o wide` | All Ready |
| Talos health | `talosctl health -n <first-cp>` | Passes |
| etcd | `talosctl etcd status -n <cp1>,<cp2>,<cp3>` | 3 healthy members |
| Ceph | `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status` | HEALTH_OK |
| Flux ks | `flux get kustomizations -A` | All Ready |
| Flux hr | `flux get helmreleases -A` | No failures |

**HARD GATE:** All checks must pass. Report specific failures.

### Phase 5: etcd Backup

```bash
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
talosctl -n $CP_NODE etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot
```

### Phase 6: Dry Run

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version> --dry-run
```

**HARD GATE:** Must succeed.

### Phase 7: Execute Upgrade

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version>
```

Wait for all nodes to show new version (`kubectl get nodes`). If no progress after 20 min, investigate with `talosctl dmesg` and `kubectl describe nodes`.

### Phase 8: Post-Upgrade Validation

Re-run Phase 4 health checks plus `kubectl version` and `kubectl get nodes -o wide`. Confirm all nodes report new version.

### Phase 9: Update Files & Report

1. Update `kubernetesVersion` in `talos/talconfig.yaml`
2. Search for **all** old version references:
   - Grep tool: search `<old-version>` (no `v` prefix) in `talos/*.yaml`, `docs/*.md`, `cluster/*.yaml`
   - **Grep may miss hookify-blocked files.** Fallback: `grep -r "v<old-version>" cluster/ --include="*.yaml" -l 2>/dev/null`. Files found only by bash need `sed -i` instead of Edit tool.
3. Common locations: `talos/talconfig.yaml`, `talos/README.md`, `cluster/flux/meta/cluster-settings.yaml`, `kubernetes-json-schema` URLs in 30+ manifest files
4. Update all references; verify zero remain
5. Present final report: version change, node status, health results, files changed

## Rollback

- `talosctl upgrade-k8s` is idempotent — re-run if it fails partway
- etcd backup from Phase 5 is primary recovery (**WARNING:** restore is destructive, resets to snapshot point)
- Debug: `talosctl -n <ip> logs kubelet`, `talosctl -n <ip> dmesg`
- Context7: `query-docs(libraryId: "/siderolabs/talos", query: "kubernetes upgrade rollback recovery")`

## Commit Pattern

```
infra(k8s): upgrade Kubernetes to v<version>

Ref #<issue-number>
```
