---
name: kubernetes-upgrade
description: This skill should be used when the user asks to "upgrade Kubernetes", "upgrade k8s", "update Kubernetes version", "bump Kubernetes version", mentions a target Kubernetes version like "upgrade to 1.35.1", or when Renovate updates kubernetesVersion in talconfig.yaml. Not for Talos OS upgrades (use talos-upgrade agent). Orchestrates safe Kubernetes upgrades with breaking change research, API deprecation scanning, cluster health gates, dry-run validation, and post-upgrade file updates.
version: 0.1.0
---

# Kubernetes Upgrade

Orchestrate safe Kubernetes version upgrades on the Talos Linux cluster. The primary value is comprehensive pre-flight safety — researching breaking changes, scanning for deprecated APIs, and gating on cluster health — before executing `talosctl upgrade-k8s`.

## Quick Reference

| Item | Value |
|------|-------|
| Upgrade command | `talosctl upgrade-k8s -n <cp-node> --to v<version>` |
| Config file | `talos/talconfig.yaml` (`kubernetesVersion` field) |
| Node topology | 3 CP (e2-1/2/3), 3 workers (ms-01-1/2/3) |
| Existing agent | `talos-upgrade` handles Talos OS upgrades (different) |
| Expected duration | 5-15 minutes for full cluster |

## Workflow

### Phase 0: Input Parsing

- Parse target version from the user's message (e.g., "upgrade to 1.35.1"). If no version is mentioned, prompt the user for one.
- Read current version from `talos/talconfig.yaml` (`kubernetesVersion` field)
- Validate format (vX.Y.Z), normalize (ensure `v` prefix for commands, strip for comparison)
- Classify: **minor** upgrade (e.g., 1.34 -> 1.35) or **patch** (e.g., 1.35.0 -> 1.35.1)
- Minor upgrades carry higher risk — enforce all gates strictly

### Phase 1: Breaking Changes Research

Consult `references/breaking-changes-lookup.md` for detailed procedures.

1. Query Context7 for Kubernetes changelog/breaking changes
2. If insufficient, fetch changelog from GitHub raw content
3. Summarize: removed APIs, deprecated APIs, behavior changes, notable features
4. Present findings to user

**HARD GATE:** Present breaking changes summary. Wait for user acknowledgment before proceeding. If removed APIs are found that match cluster resources, recommend aborting until remediated.

### Phase 2: Cluster API Compatibility Scan

Consult `references/api-deprecation-scanning.md` for detailed procedures.

1. From Phase 1, identify APIs being removed in target version
2. Scan live cluster via kubectl:
   ```bash
   # Check deprecated API metrics
   kubectl get --raw /metrics 2>/dev/null | grep apiserver_requested_deprecated_apis | grep 'removed_release="<minor>"'
   # Direct resource queries for each removed API
   kubectl get <resource>.<api-group> --all-namespaces 2>/dev/null
   ```
3. Scan git manifests using the Grep tool for deprecated `apiVersion` strings in `cluster/`
4. Report findings with namespace/resource/kind

**HARD GATE:** If removed APIs are in active use, BLOCK upgrade. List resources requiring migration.

### Phase 3: Talos Compatibility Check

Verify Talos supports the target Kubernetes version:

1. Read current Talos version from `talos/talconfig.yaml` (`talosVersion` field)
2. Check Talos support matrix via Context7:
   ```
   query-docs(libraryId: "/siderolabs/talos", query: "supported kubernetes versions for Talos v<current-talos>")
   ```
3. General rule: Talos v1.x supports K8s versions within its tested range

**HARD GATE:** If Talos version is incompatible, BLOCK. Recommend running Talos upgrade first via `talos-upgrade` agent.

### Phase 4: Cluster Health Gate

Discover control plane node IPs dynamically (never hardcode):

```bash
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
```

Run all checks. BLOCK on any failure.

```bash
# Parallel Group 1 - Nodes
kubectl get nodes -o wide
talosctl health -n <first-cp-ip>

# Parallel Group 2 - etcd and Ceph
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Parallel Group 3 - GitOps
flux get kustomizations -A
flux get helmreleases -A
```

**Pass criteria:** All nodes Ready, talosctl health passes, etcd 3 healthy members, Ceph HEALTH_OK, all Flux kustomizations Ready, no failing HelmReleases.

**HARD GATE:** All checks must pass. Report specific failures.

### Phase 5: etcd Backup

Mandatory before upgrade:

```bash
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
talosctl -n $CP_NODE etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot
```

Verify snapshot created successfully.

### Phase 6: Dry Run

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version> --dry-run
```

Report what will change.

**HARD GATE:** Dry run must succeed. Report errors if it fails.

### Phase 7: Execute Upgrade

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version>
```

Monitor: `kubectl get nodes` — wait for all nodes to show new version. Expect 5-15 minutes for the full cluster. If no progress after 20 minutes, investigate with `talosctl dmesg` and `kubectl describe nodes`.

### Phase 8: Post-Upgrade Validation

Re-run Phase 4 health checks plus version verification:

```bash
kubectl version
kubectl get nodes -o wide
```

Confirm all nodes report new Kubernetes version. Report any regressions.

### Phase 9: Update Files & Report

1. Update `kubernetesVersion` in `talos/talconfig.yaml` to match new version
2. Search for old version references using the Grep tool: search for `v<old-version>` in `talos/` with glob `*.yaml`, and in `docs/` with glob `*.md`
3. Update any found references using the Edit tool
4. Present final report:
   - Version change (from -> to)
   - Node status table
   - Health check results
   - Files changed
   - Ready for commit

## Rollback

If the upgrade fails or causes issues:

- `talosctl upgrade-k8s` can be re-run if it fails partway through — it is idempotent
- The etcd backup from Phase 5 is the primary recovery mechanism. **WARNING: etcd restore is destructive and resets cluster state to the snapshot point. Only use as a last resort.**
  ```bash
  talosctl -n <cp-node> etcd snapshot restore /tmp/etcd-backup-<timestamp>.snapshot
  ```
- If specific components fail to start after upgrade, check logs:
  ```bash
  talosctl -n <node-ip> logs kubelet
  talosctl -n <node-ip> dmesg
  ```
- For critical failures, consult Talos docs via Context7:
  ```
  query-docs(libraryId: "/siderolabs/talos", query: "kubernetes upgrade rollback recovery")
  ```

## GitHub Issue Tracking

Create or reference a tracking issue per project workflow:

```bash
gh issue create --repo anthony-spruyt/spruyt-labs \
  --title "infra(k8s): upgrade Kubernetes v<current> to v<target>" \
  --label "infra" \
  --body "..."
```

Post progress updates as issue comments after each phase.

## Commit Pattern

```
infra(k8s): upgrade Kubernetes to v<version>

Ref #<issue-number>
```

## Additional Resources

### Reference Files

- **`references/breaking-changes-lookup.md`** — Detailed procedures for researching K8s breaking changes via Context7, GitHub, changelogs
- **`references/api-deprecation-scanning.md`** — kubectl commands, metrics queries, and remediation for deprecated API scanning
