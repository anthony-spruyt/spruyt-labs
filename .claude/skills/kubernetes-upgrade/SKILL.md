---
name: kubernetes-upgrade
description: Use when the user asks to upgrade or bump the Kubernetes (k8s) version, with or without a target such as 1.35.1, or when Renovate updates kubernetesVersion in topf.yaml. Not for Talos OS upgrades (use talos-upgrade skill).
argument-hint: <target-version>
---

# Kubernetes Upgrade

Orchestrate safe Kubernetes version upgrades on Talos Linux. Primary value: comprehensive pre-flight safety before `talosctl upgrade-k8s`.

## Quick Reference

| Item            | Value                                                                    |
| --------------- | ------------------------------------------------------------------------ |
| Upgrade command | `talosctl upgrade-k8s -n <cp-node> --to v<version> --manifests-no-prune` |
| Config file     | `talos/topf.yaml` (`kubernetesVersion` field)                            |
| Node topology   | 3 CP (e2-1/2/3), 3 workers (ms-01-1/2/3)                                 |
| Talos OS skill  | `talos-upgrade` (different from this skill)                              |

## Workflow

### Phase 1: Input Parsing

- Parse target version from user message; prompt if missing
- Read current version from `talos/topf.yaml` (`kubernetesVersion`)
- Classify: **minor** (1.34→1.35, higher risk) or **patch** (1.35.0→1.35.1)

### Phase 2: Create GitHub Issue

Find or create the issue per the GitHub rule (search first), filling the body from the fields of `.github/ISSUE_TEMPLATE/infra.yml` (the infra form, one `## <field label>` heading per form field) so SRE agents see maintenance context. Include:

- Title: `chore(k8s): upgrade Kubernetes to v<version>`
- Label: `infra`
- Why: summary and motivation (Renovate PR link if applicable)
- What: upgrade type (patch vs minor), the components it touches, and the planned steps
- Rollback: the rollback plan
- Done when: how to check the upgrade worked
- Track issue number for commit references (`Ref #<number>`)

### Phase 3: Breaking Changes Research

Consult `references/breaking-changes-lookup.md` for procedures.

**HARD GATE:** Present findings. Wait for user acknowledgment. If removed APIs match cluster resources, recommend aborting.

### Phase 4: Cluster API Compatibility Scan

Consult `references/api-deprecation-scanning.md` for procedures.

**HARD GATE:** If removed APIs are in active use, BLOCK. List resources requiring migration.

### Phase 5: Talos Compatibility Check

1. Read Talos version from `talos/topf.yaml` (`talosVersion`)
2. Query Context7: `query-docs(libraryId: "/siderolabs/talos", query: "supported kubernetes versions for Talos v<current>")`

**HARD GATE:** If incompatible, BLOCK. Recommend `talos-upgrade` skill first.

### Phase 6: Cluster Health Gate

Discover CP node IPs dynamically:

```bash
CP_NODES=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
```

| Check        | Command                                                           | Pass Criteria     |
| ------------ | ----------------------------------------------------------------- | ----------------- |
| Nodes        | `kubectl get nodes -o wide`                                       | All Ready         |
| Talos health | `talosctl health -n <first-cp>`                                   | Passes            |
| etcd         | `talosctl etcd status -n <cp1>,<cp2>,<cp3>`                       | 3 healthy members |
| Ceph         | `kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status` | HEALTH_OK         |
| Flux ks      | `flux get kustomizations -A`                                      | All Ready         |
| Flux hr      | `flux get helmreleases -A`                                        | No failures       |

Talos must neither render nor track CoreDNS (Flux owns it). Both commands must print `true`:

```bash
talosctl -n <first-cp> get manifests -o json | jq -se 'length > 0 and ([.[].metadata.id | select(test("core-dns"))] | length == 0)'
kubectl -n kube-system get cm talos-bootstrap-manifests-inventory -o json | jq -e '[.data | keys[] | select(test("coredns|kube-dns"))] | length == 0'
```

**HARD GATE:** All checks must pass. Report specific failures.

### Phase 7: etcd Backup

```bash
CP_NODE=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
talosctl -n $CP_NODE etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot
```

### Phase 8: Dry Run

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version> --dry-run
```

**HARD GATE:** All must hold, else STOP and report the object names to the user, never the diff output:

- The dry run succeeds
- No ` < Pruned ` line
- No ` < configured ` diff touches a Flux-owned object, except an annotation-only `config.k8s.io/owning-inventory` addition (today: the two VPA CRDs). Flux-owned means the live object has a `kustomize.toolkit.fluxcd.io/name` or `helm.toolkit.fluxcd.io/name` label, which every CRD from `talos/patches/control-plane/07-extra-manifests.yaml` has

### Phase 9: Execute Upgrade

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version> --manifests-no-prune
```

`--manifests-no-prune` stays on every run: Phase 8 shows nothing to prune, and the flag keeps it that way if the cluster changed since.

Wait for all nodes to show new version (`kubectl get nodes`). If no progress after 20 min, investigate with `talosctl dmesg` and `kubectl describe nodes`.

### Phase 10: Post-Upgrade Validation

Re-run Phase 6 health checks plus `kubectl version` and `kubectl get nodes -o wide`. Confirm all nodes report new version.

### Phase 11: Roll Stale Secret Volume Mounts

K8s upgrades restart all kubelets. After restart, kubelet's `Watch`-based secret manager fails to re-establish watches for pre-existing pods' volume mounts. Secrets mounted as volumes become frozen at the pre-upgrade state.

**Detection:** For every Running pod with a secret volume (non-subPath), exec `stat -c %Y <mount>/..data` and compare against the kubelet restart time. If the `..data` symlink timestamp predates the kubelet restart, the mount is stale.

**Roll order (sequential, not parallel):**

1. **Safe tier** — stateless or independently restartable. Roll all at once:

   - `kubectl rollout restart` for Deployments
   - `kubectl delete pod` for StatefulSets (one at a time, wait for Ready)
   - Namespaces: observability, authentik-system, cnpg plugins, nexus-system, app workloads

2. **DNS tier** — technitium primary + secondary:

   - Roll secondary first, wait for Ready
   - Roll primary, wait for Ready
   - Verify: `dig @<technitium-ip> <any-internal-record>`

3. **Storage tier** — rook-ceph (mons, mgrs, rgws, crashcollectors, exporters, tools):

   - **Before each restart:** `ceph status` must show HEALTH_OK (HEALTH_WARN acceptable only for expected warnings)
   - Roll one pod at a time, wait for Ready + Ceph health between each
   - Order: tools → crashcollectors → exporters → rgw → mgr(s) → mons (one at a time)
   - **STOP if Ceph goes HEALTH_ERR** — investigate before continuing

4. **Skip:** Pods where stat failed (subPath mounts) — these read at pod start and don't use the `..data` symlink mechanism

**Report:** List what was rolled and current health after completion.

### Phase 12: Update Files & Report

1. Search for **all** old version references. Search without the `v` prefix so both `v1.x.y` and `1.x.y` forms match:
   - `grep -rln --include='*.yaml' --include='*.md' --include='*.sh' -F '<old-version>' talos/ docs/ cluster/ .github/workflows/ .taskfiles/`
2. Common locations: `talos/topf.yaml` (`kubernetesVersion`), `.github/workflows/ci-repo.yaml` (`KUBERNETES_VERSION`), `.taskfiles/install/scripts/install-kubectl.sh` (`VERSION`)
3. Land the version change:
   - **Started from a Renovate PR:** it already bumps the files Renovate tracks. If step 1 found other references, update them on the PR branch, run qa-validator with the issue number and changed files, and land them per the `orchestration` skill (fresh reviewer READY, `push-reviewed.sh` to the PR branch). Then `gh pr merge <N> --squash`
   - **Otherwise:** update every reference, run qa-validator with the issue number and changed files, then land it per the `orchestration` skill, as in `talos-upgrade`'s landing rule
   - Either way, run cluster-validator if a changed file is under `cluster/`
4. Verify zero old references remain on `main` and `task talos:diff` exits 0, then close the issue
5. Present final report: version change, node status, health results, files changed

## Rollback

- `talosctl upgrade-k8s` is idempotent — re-run the Phase 9 command if it fails partway
- etcd backup from Phase 7 is primary recovery (**WARNING:** restore is destructive, resets to snapshot point)
- Debug: `talosctl -n <ip> logs kubelet`, `talosctl -n <ip> dmesg`
- Context7: `query-docs(libraryId: "/siderolabs/talos", query: "kubernetes upgrade rollback recovery")`

## Commit Pattern

```text
chore(k8s): upgrade Kubernetes to v<version>

Ref #<issue-number>
```
