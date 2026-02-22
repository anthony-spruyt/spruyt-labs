# Design: CronJob-Aware Validation for cluster-validator

**Date:** 2026-02-22
**Issue:** #519
**Status:** Approved

## Problem

The cluster-validator agent validated a descheduler Helm chart upgrade (v0.34.0 to v0.35.0) by checking the most recent completed CronJob run. That run was from the *previous* chart version (v0.34.0), so validation passed. The actual v0.35.0 binary was broken (missing PVC RBAC in the chart's ClusterRole), but the bug wasn't caught until the next CronJob trigger 30 minutes later.

## Root Cause

The cluster-validator has no concept of workload-type-aware validation. For Deployments and StatefulSets, Flux triggers a rollout immediately, so checking pod health works. For CronJobs, Flux only updates the CronJob template — no new pod runs until the next schedule trigger. Validating a CronJob upgrade by looking at the last completed job is validating stale state.

## Solution

Add CronJob-specific validation to the cluster-validator agent. When the upgraded workload is a CronJob, manually trigger a test job from the updated template and validate its completion.

### Detection

After identifying the affected HelmRelease/namespace, check if the primary workload is a CronJob:

```bash
kubectl get cronjobs -n <ns> -l app.kubernetes.io/name=<app>
```

### Validation Flow

1. Create a test job from the CronJob template:
   ```bash
   kubectl create job <app>-validate-<short-hash> --from=cronjob/<app> -n <ns>
   ```
2. Wait for completion with timeout:
   ```bash
   kubectl wait --for=condition=complete job/<name> -n <ns> --timeout=120s
   ```
3. On success: check pod logs for errors (some jobs "complete" with error output)
4. On timeout/failure: capture pod logs, include in failure report
5. Clean up the test job regardless of outcome:
   ```bash
   kubectl delete job <name> -n <ns>
   ```

### Failure Classification

CronJob test failures are classified as **HIGH severity** — the workload is fundamentally broken even though nothing else in the cluster is affected. Default action: ROLLBACK.

### Scope

- Additive change to `cluster-validator.md` only
- New section under "Common Validation Scenarios": **CronJob / Batch Workload Upgrade**
- New entry in Change-Type Detection table
- No changes to the renovate-pr-processor skill or renovate-pr-analyzer agent

### Why This Catches the Descheduler Bug

With this change, the validator would have:
1. Detected `descheduler` is a CronJob
2. Created `descheduler-validate-<hash>` job from the updated v0.35.0 template
3. Watched it hang retrying PVC list (RBAC forbidden)
4. Timed out at 120s
5. Captured the error logs showing `persistentvolumeclaims is forbidden`
6. Reported ROLLBACK with evidence
