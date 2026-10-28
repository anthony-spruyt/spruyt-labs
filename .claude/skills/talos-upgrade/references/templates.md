# Issue and Outcome Templates

The issue is public. In every template posted there, name nodes by hostname, and strip IPs and network details from any command output first: `talosctl etcd status` and talosctl dial errors print node IPs.

## Issue body

Create the issue with title `chore(talos): upgrade Talos v<current> to v<target>` and label `infra`. Fill the body from the fields of `.github/ISSUE_TEMPLATE/infra.yml` (the infra form), with one `## <field label>` heading per form field to match the form layout, using these upgrade-specific values:

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
[Command output showing failure, node names only, IPs stripped]

### Required Action
[What needs to be fixed before upgrade can proceed]
```

## WORKER UPGRADE BLOCKED (Step 4.1, Step 4.4b)

```text
## WORKER UPGRADE BLOCKED

### Reason
[Step 4.1: Ceph is not ready. Step 4.4b: the GPU gate failed on <hostname>.]

### Current Status
[Step 4.1: ceph status and ceph health detail output. Step 4.4b: the gate's failing output. IPs stripped.]

### Required Action
[Step 4.1: wait for Ceph to be ready before upgrading the next worker; this may take 5-30 minutes depending on rebalancing. Step 4.4b: fix the node's GPU before any other node or phase.]

### Command to Monitor
[Step 4.1: kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status. Step 4.4b: the Step 4.4b block in workers.md.]
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
[Command output showing failure, node names only, IPs stripped]

### Rollback Status
- **Rolled back**: <yes/no/partial>
- **Current state**: <description>

### Required Actions
1. [Specific rollback steps if not complete]
2. [Investigation steps]
```

## PARTIAL

Put the question first, with at most 2 options and a recommendation. Pick the options that fit, such as **Wait** (Ceph is recovering: wait for HEALTH_OK), **Resume** (the issue is resolved: continue with the remaining nodes), **Rollback** (a critical issue: roll back all nodes).

```text
## UPGRADE PARTIAL - INTERVENTION REQUIRED

### Question
[The decision needed, with the context to answer it]

### Options
1. **<option>** (recommended): <why>
2. **<option>**: <why>

### Progress
- **Upgraded**: <list of upgraded nodes>
- **Pending**: <list of pending nodes>
- **Failed**: <list of failed nodes, if any>

### Blocked On
[Why upgrade cannot continue]

### Required Actions
1. [Steps left to finish the upgrade, in order]

### Current State
[kubectl get nodes output, IPs stripped]
[ceph status if relevant]
```
