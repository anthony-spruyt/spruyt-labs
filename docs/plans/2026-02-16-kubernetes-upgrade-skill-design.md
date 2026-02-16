# Kubernetes Upgrade Skill Design

## Overview

A Claude Code skill that orchestrates Kubernetes version upgrades on the Talos Linux homelab cluster. The skill's primary value is comprehensive pre-flight safety checks — researching breaking changes, scanning for deprecated APIs in live cluster resources, and gating on cluster health — before executing the straightforward `talosctl upgrade-k8s` command.

## Context

- **Cluster**: 3 control plane nodes (e2-1/2/3), 3 workers (ms-01-1/2/3)
- **Current stack**: Talos v1.12.4, Kubernetes v1.35.0
- **Existing tooling**: `talos-upgrade` agent handles Talos OS upgrades; no equivalent for Kubernetes upgrades
- **Upgrade mechanism**: `talosctl upgrade-k8s -n <cp-node> --to <version>`

## Skill Structure

```
.claude/skills/kubernetes-upgrade/
├── SKILL.md                            # Core workflow (~1,500-2,000 words)
└── references/
    ├── breaking-changes-lookup.md      # How to research K8s breaking changes
    └── api-deprecation-scanning.md     # Detailed API scanning procedures
```

### Frontmatter

```yaml
---
name: kubernetes-upgrade
description: >-
  This skill should be used when the user asks to "upgrade Kubernetes",
  "upgrade k8s", "update Kubernetes version", mentions a target Kubernetes
  version like "upgrade to 1.35.1", or when Renovate updates
  kubernetesVersion in talconfig.yaml. Orchestrates safe Kubernetes
  upgrades with breaking change research, API deprecation scanning,
  cluster health gates, and post-upgrade file updates.
argument-hint: "[target-version]"
---
```

### Argument Handling

- `$0` = target version (e.g., `1.35.1` or `v1.35.1`)
- If no argument provided, prompt user for target version
- Normalize version format (strip leading `v` if present for comparison, add it for commands)

## Phases

### Phase 0: Input Parsing

- Accept target version from `$0` or user prompt
- Read current `kubernetesVersion` from `talos/talconfig.yaml`
- Validate version format (vX.Y.Z)
- Determine version delta (minor vs patch upgrade — minor upgrades are riskier)

### Phase 1: Breaking Changes Research

**Research priority**: Context7 -> GitHub -> WebFetch -> WebSearch (per CLAUDE.md rules)

1. Resolve Kubernetes library in Context7, query for changelog/breaking changes for target version
2. If Context7 lacks detail, fetch the official changelog from GitHub (`raw.githubusercontent.com/kubernetes/kubernetes/master/CHANGELOG/CHANGELOG-<minor>.md`)
3. Summarize:
   - Removed APIs
   - Deprecated APIs (will be removed in future)
   - Breaking behavior changes
   - Notable new features relevant to cluster
4. Present findings to user

**HARD GATE**: User must acknowledge breaking changes before proceeding. If critical breaking changes found (removed APIs in use), recommend aborting.

Detailed lookup procedures go in `references/breaking-changes-lookup.md`.

### Phase 2: Cluster API Compatibility Scan

Scan live cluster for resources using APIs deprecated or removed in the target version.

1. Identify which API versions are being removed in target version (from Phase 1 research)
2. For each removed API, check if cluster has resources using it:
   ```bash
   kubectl get <resource>.<deprecated-api-group> --all-namespaces 2>/dev/null
   ```
3. Also check via metrics if available:
   ```bash
   kubectl get --raw /metrics | grep apiserver_request_total | grep <deprecated-group>
   ```
4. Report findings — list of resources using deprecated APIs with namespace/name

**HARD GATE**: If removed APIs are actively in use, BLOCK upgrade and list resources that must be migrated first.

Detailed scanning procedures go in `references/api-deprecation-scanning.md`.

### Phase 3: Talos Compatibility Check

Verify current Talos version supports the target Kubernetes version.

1. Check Talos support matrix (Context7 for Talos docs, or known compatibility)
2. General rule: Talos minor version X.Y supports K8s versions within a compatible range
3. If Talos needs upgrading first, BLOCK and recommend running Talos upgrade first (via `talos-upgrade` agent)

**HARD GATE**: Talos version must support target K8s version.

### Phase 4: Cluster Health Gate

All checks must pass. Reuses patterns from `talos-upgrade` agent.

```bash
# Parallel Group 1 - Node and cluster health
kubectl get nodes -o wide
talosctl health -n <any-cp-node>

# Parallel Group 2 - etcd and storage
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status

# Parallel Group 3 - GitOps
flux get kustomizations -A
flux get helmreleases -A
```

**Pass criteria:**
- All nodes Ready
- talosctl health passes
- etcd: 3 healthy members with consistent terms
- Ceph: HEALTH_OK
- All Flux kustomizations Ready
- No failing HelmReleases

**HARD GATE**: All health checks must pass.

### Phase 5: etcd Backup

Mandatory before any upgrade.

```bash
CP_NODE=<first-cp-ip>
talosctl -n $CP_NODE etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d-%H%M%S).snapshot
```

Verify snapshot was created successfully.

### Phase 6: Dry Run

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version> --dry-run
```

Review dry-run output. Report what will change.

**HARD GATE**: Dry run must succeed without errors.

### Phase 7: Execute Upgrade

```bash
talosctl upgrade-k8s -n <cp-node-ip> --to v<version>
```

Monitor progress:
```bash
kubectl get nodes -w
```

Wait for all nodes to report new version.

### Phase 8: Post-Upgrade Validation

```bash
# Parallel Group 1 - Version verification
kubectl get nodes -o wide
kubectl version

# Parallel Group 2 - Cluster health
talosctl health -n <any-cp-node>
talosctl etcd status -n <cp-ip-1>,<cp-ip-2>,<cp-ip-3>

# Parallel Group 3 - Storage and GitOps
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
flux get kustomizations -A
flux get helmreleases -A
```

All checks from Phase 4 must pass again. Report any regressions.

### Phase 9: Update Files & Report

1. Update `kubernetesVersion` in `talos/talconfig.yaml`
2. Update any version references in docs (grep for old version)
3. Present final summary report:
   - From version -> To version
   - All nodes showing new version
   - Health check results
   - Files changed
   - Ready to commit

## Hard Gates Summary

| Gate | Between | Condition | Block Action |
|------|---------|-----------|--------------|
| Breaking changes | Phase 1 -> 2 | User acknowledges findings | Present findings, wait for go-ahead |
| API compatibility | Phase 2 -> 3 | No removed APIs in active use | List resources to migrate |
| Talos compat | Phase 3 -> 4 | Talos supports target K8s | Recommend Talos upgrade first |
| Health | Phase 4 -> 5 | All checks pass | Report failures |
| Dry run | Phase 6 -> 7 | Dry run succeeds | Report errors |

## GitHub Issue Tracking

Follow project workflow rules:
- Create issue if none exists: `infra(k8s): upgrade Kubernetes v<current> to v<target>`
- Label: `infra`
- Post progress updates as issue comments
- Reference issue in commit

## File Changes

After successful upgrade, the skill modifies:
- `talos/talconfig.yaml` — `kubernetesVersion` field
- Any docs referencing the old K8s version

## Commit Pattern

```
infra(k8s): upgrade Kubernetes to v<version>

Ref #<issue-number>
```

## Progressive Disclosure

### SKILL.md (~1,800 words)
- Core workflow overview
- Phase sequence with gates
- Key commands for each phase
- Pointers to reference files

### references/breaking-changes-lookup.md
- Detailed procedures for researching K8s breaking changes
- Context7 query patterns
- GitHub changelog URLs by version
- How to interpret changelog entries

### references/api-deprecation-scanning.md
- Complete list of common API deprecation patterns across K8s versions
- kubectl commands for scanning each resource type
- Metrics-based detection methods
- Migration guidance patterns
