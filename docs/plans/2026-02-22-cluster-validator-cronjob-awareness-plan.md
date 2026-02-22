# Cluster-Validator CronJob Awareness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make cluster-validator trigger a manual test job when validating CronJob-based workloads, instead of relying on stale previous runs.

**Architecture:** Additive change to the cluster-validator agent prompt. Adds CronJob detection to the change-type table and a new validation scenario with manual job trigger, wait, log check, and cleanup.

**Tech Stack:** Markdown (agent prompt), kubectl, Kubernetes Jobs/CronJobs

---

### Task 1: Add CronJob entry to Change-Type Detection table

**Files:**
- Modify: `.claude/agents/cluster-validator.md` (Change-Type Detection table, around line 42-53)

**Step 1: Add the new row**

In the Change-Type Detection table, add a row after `helm-release`:

```markdown
| `cronjob-workload` | HelmRelease where primary resource is CronJob | CronJob template, manual test job, pod logs | Deployment/StatefulSet rollout checks |
```

**Step 2: Commit**

```bash
git add .claude/agents/cluster-validator.md
git commit -m "feat(cluster-validator): add cronjob-workload to change-type detection table

Ref #519"
```

---

### Task 2: Add CronJob validation scenario

**Files:**
- Modify: `.claude/agents/cluster-validator.md` (Common Validation Scenarios section, after line 444)

**Step 1: Add the new scenario section**

After the "### Infrastructure Change" scenario block (ends around line 444), add:

````markdown
### CronJob / Batch Workload Upgrade

CronJobs don't trigger new pods on Flux reconciliation — only the template is updated. You MUST manually trigger a test job to validate the upgrade actually works.

**Step 1: Detect CronJob workloads**

After identifying the affected HelmRelease and namespace, check if the primary workload is a CronJob:

```bash
kubectl get cronjobs -n <namespace> -l app.kubernetes.io/name=<app>
```

If a CronJob is found, do NOT rely on the last completed job — it ran the previous version.

**Step 2: Trigger a manual test job**

```bash
# Create a one-off job from the updated CronJob template
kubectl create job <app>-validate-$(date +%s) --from=cronjob/<app> -n <namespace>
```

**Step 3: Wait for completion**

```bash
# Wait with 120s timeout — most CronJobs complete in seconds
kubectl wait --for=condition=complete job/<job-name> -n <namespace> --timeout=120s
```

**Step 4: Check job logs**

Even if the job "completes", check logs for errors (some jobs exit 0 despite errors):

```bash
kubectl logs job/<job-name> -n <namespace> --tail=50
```

Look for: error messages, permission denied, RBAC forbidden, connection refused, crash traces.

**Step 5: Clean up**

```bash
kubectl delete job <job-name> -n <namespace>
```

**Failure handling:**
- If the job times out or fails → severity is **HIGH**, default action is **ROLLBACK**
- Capture the pod logs and include them verbatim in the failure report
- The CronJob template is broken — every future scheduled run will also fail
````

**Step 2: Commit**

```bash
git add .claude/agents/cluster-validator.md
git commit -m "feat(cluster-validator): add CronJob manual test job validation

When validating upgrades to CronJob-based workloads, trigger a manual
test job instead of relying on stale previous runs. Catches RBAC,
config, and runtime errors immediately rather than on next schedule.

Ref #519"
```

---

### Task 3: Add CronJob entry to Resource-Specific Validation Matrix

**Files:**
- Modify: `.claude/agents/cluster-validator.md` (Resource-Specific Validation Matrix table, around line 266-278)

**Step 1: Add the new row**

In the Resource-Specific Validation Matrix table, add after the Pod row:

```markdown
| **CronJob** | Test job completes, logs clean | Test job timeout, RBAC errors, crash in logs | `kubectl create job --from=cronjob/<name>`, `kubectl wait`, `kubectl logs` |
```

**Step 2: Commit**

```bash
git add .claude/agents/cluster-validator.md
git commit -m "feat(cluster-validator): add CronJob to resource validation matrix

Ref #519"
```

---

### Task 4: Verify and final commit

**Step 1: Read the modified file**

Read `.claude/agents/cluster-validator.md` end-to-end to verify:
- Change-Type Detection table has the new `cronjob-workload` row
- Resource-Specific Validation Matrix has the CronJob row
- Common Validation Scenarios has the full CronJob section
- No formatting issues or broken markdown

**Step 2: Squash into single commit (optional)**

If the user prefers a single commit, squash tasks 1-3. Otherwise leave as incremental commits.
