# Issue and Outcome Templates

## Issue body

Fill the body from the fields of `.github/ISSUE_TEMPLATE/infra.yml` (the infra form), with one `## <field label>` heading per form field to match the form layout, using these upgrade-specific values:

- Why: upgrade Talos Linux across all cluster nodes; Renovate PR, security patches or feature requirements; link the Renovate PR, if any
- What: Talos (machine configs, upgrades) on all control plane and worker nodes, with these steps (plain numbered list):
  1. Pre-upgrade validation (etcd backup, cluster health)
  2. Pre-flight drift check; apply pending `talos/` changes already on main (`task talos:diff`)
  3. Config migration and `talosctl validate` (minor upgrades only)
  4. Upgrade control plane nodes (sequential)
  5. Upgrade worker nodes (sequential, Ceph health gates)
  6. Post-upgrade validation
  7. Trigger descheduler for workload rebalancing
  8. Update talos/README.md on main
  9. Land the talosVersion pin, diff, and `task talos:apply`
- Rollback: downgrade the affected node using the previous version image; restore etcd from snapshot if corrupted; if Ceph is degraded, wait for recovery before the next action
- Done when: etcd 3/3 healthy, all nodes Ready on v<target>, Ceph ready (Step 4.1); `task talos:diff` clean after apply

## Progress comment

Post progress updates as issue comments. Example body:

```markdown
## Progress Update

### Control Plane Upgrades
- e2-1: ✅ Upgraded to v<version>
- e2-2: ✅ Upgraded to v<version>
- e2-3: 🔄 In progress...

### etcd Status
3/3 members healthy
```

## PRE-UPGRADE BLOCKED (Phase 1)

```text
## PRE-UPGRADE BLOCKED

### Failed Check
[Which check failed]

### Evidence
[Command output showing failure]

### Required Action
[What needs to be fixed before upgrade can proceed]
```

## WORKER UPGRADE BLOCKED (Step 4.1)

```text
## WORKER UPGRADE BLOCKED

### Reason
Ceph is not ready - cannot proceed with worker upgrade.

### Current Ceph Status
[ceph status and ceph health detail output]

### Required Action
Wait for Ceph to be ready before upgrading next worker.
This may take 5-30 minutes depending on rebalancing.

### Command to Monitor
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
```

## Upgrade Complete (Phase 9)

```text
## Upgrade Complete

### Summary
- **From**: v<old-version>
- **To**: v<new-version>
- **Nodes Upgraded**: 6/6
- **Duration**: Xh Ym

### Node Status
| Node | Role | Version | Status |
|------|------|---------|--------|
| ... | CP | v<new> | Ready |
| ... | Worker | v<new> | Ready |

### Health Checks
- etcd: 3/3 members healthy
- Ceph: ready (Step 4.1); list any allowed warning still present
- Flux: All kustomizations Ready

### Config
- talos/README.md: updated on main (<commit>)
- talosVersion pin: on main (<commit or PR #>)
- task talos:apply: done, post-apply diff clean

### Validation
- cluster-validator: <verdict, or not run: the pin PR did not touch `cluster/`>
```

## SUCCESS

```text
## UPGRADE COMPLETE - SUCCESS

### Summary
- All nodes upgraded to v<new-version>
- etcd quorum: 3/3 healthy
- Ceph: ready (Step 4.1); list any allowed warning still present
- talos/README.md: updated on main
- Machine config: applied, `task talos:diff` clean

### Commits on main
- talos/README.md

### Validation
- cluster-validator: <verdict, or not run: the pin PR did not touch `cluster/`>
- Tracking issue: closed
```

## ROLLBACK

```text
## UPGRADE FAILED - ROLLBACK REQUIRED

### Failure Point
- **Node**: <hostname>
- **Phase**: <which phase failed>
- **Error**: <error description>

### Evidence
[Command output showing failure]

### Rollback Status
- **Rolled back**: <yes/no/partial>
- **Current state**: <description>

### Required Actions
1. [Specific rollback steps if not complete]
2. [Investigation steps]
```

## PARTIAL

```text
## UPGRADE PARTIAL - INTERVENTION REQUIRED

### Progress
- **Upgraded**: <list of upgraded nodes>
- **Pending**: <list of pending nodes>
- **Failed**: <list of failed nodes, if any>

### Blocked On
[Why upgrade cannot continue]

### Options
1. **Wait**: If Ceph is recovering, wait for HEALTH_OK
2. **Resume**: If issue resolved, continue with remaining nodes
3. **Rollback**: If critical issue, rollback all nodes

### Current State
[kubectl get nodes output]
[ceph status if relevant]
```
