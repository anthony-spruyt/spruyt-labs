# ServiceAccount Token Automount Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent unnecessary Kubernetes API token mounting across all workloads by requiring every pod spec to explicitly declare `automountServiceAccountToken`.

**Architecture:** Four layers — fix all existing workloads (raw manifests + HelmRelease values/postRenderers), Kyverno mutate policy for uncontrollable pods, Kyverno validate policy to enforce going forward, and SA hardening for pods on default SA. Rollout order: fix workloads → mutate → validate → recreate outpost pods.

**Tech Stack:** Kubernetes YAML, Kyverno ClusterPolicy, Flux HelmRelease postRenderers, Kustomize

**Issue:** #576 **Spec:** `docs/superpowers/specs/2026-05-10-sa-automount-hardening-design.md`

______________________________________________________________________

## File Map

| File                                                                                     | Action | Responsibility                                             |
| ---------------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------- |
| `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml`         | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml`                      | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/github-system/bot-ssh-key-rotation/app/cronjob.yaml`                       | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/coder-workspaces/ssh-key-rotation/app/cronjob.yaml`                        | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/restart-cronjob.yaml`  | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml` | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml`        | Modify | Add `automountServiceAccountToken: true`                   |
| `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml`                           | Modify | Add `automountServiceAccountToken: false` to pod spec      |
| `cluster/apps/authentik-system/authentik/app/values.yaml`                                | Modify | Set `server.serviceAccountName: authentik`                 |
| `cluster/apps/authentik-system/authentik/app/release.yaml`                               | Modify | Add postRenderer for `automountServiceAccountToken: false` |
| `cluster/apps/firefly-iii/firefly-iii/app/release.yaml`                                  | Modify | Add postRenderer patches for Deployment + CronJob          |
| `cluster/apps/observability/victoria-logs-single/app/values.yaml`                        | Modify | Add `serviceAccount.create: true`, `automountToken: false` |
| `cluster/apps/observability/victoria-traces-single/app/values.yaml`                      | Modify | Add `serviceAccount.create: true`, `automountToken: false` |
| `cluster/apps/kyverno/policies/app/require-explicit-automount.yaml`                      | Create | Validate policy (enforce)                                  |
| `cluster/apps/kyverno/policies/app/inject-automount-false-exceptions.yaml`               | Create | Mutate policy for Authentik outposts                       |
| `cluster/apps/kyverno/policies/app/kustomization.yaml`                                   | Modify | Register new policy files                                  |

______________________________________________________________________

### Task 1: Raw Manifests — Add `automountServiceAccountToken: true`

**Files:**

- Modify: `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml:17` (pod spec)
- Modify: `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml:21` (pod spec)
- Modify: `cluster/apps/github-system/bot-ssh-key-rotation/app/cronjob.yaml:21` (pod spec)
- Modify: `cluster/apps/coder-workspaces/ssh-key-rotation/app/cronjob.yaml:21` (pod spec)
- Modify: `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/restart-cronjob.yaml:63` (pod spec)
- Modify: `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml:44` (pod spec)
- Modify: `cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml:35` (pod spec)

These workloads use kubectl or the Kubernetes API and need the SA token. The field goes at `spec.template.spec.automountServiceAccountToken` (or `spec.jobTemplate.spec.template.spec.automountServiceAccountToken` for CronJobs).

- [ ] **Step 1: Add field to oauth-secret-rotation cronjob**

In `cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml`, add `automountServiceAccountToken: true` after `serviceAccountName` in the pod spec (line 22):

```yaml
          serviceAccountName: oauth-secret-rotation
          automountServiceAccountToken: true
```

- [ ] **Step 2: Add field to github-token-rotation cronjob**

In `cluster/apps/github-system/github-token-rotation/app/cronjob.yaml`, add after `serviceAccountName` in pod spec:

```yaml
          serviceAccountName: github-token-rotation
          automountServiceAccountToken: true
```

- [ ] **Step 3: Add field to bot-ssh-key-rotation cronjob**

In `cluster/apps/github-system/bot-ssh-key-rotation/app/cronjob.yaml`, add after `serviceAccountName` in pod spec:

```yaml
          serviceAccountName: bot-ssh-key-rotation
          automountServiceAccountToken: true
```

- [ ] **Step 4: Add field to ssh-key-rotation cronjob**

In `cluster/apps/coder-workspaces/ssh-key-rotation/app/cronjob.yaml`, add after `serviceAccountName` in pod spec:

```yaml
          serviceAccountName: ssh-key-rotation
          automountServiceAccountToken: true
```

- [ ] **Step 5: Add field to csi-addons-restart cronjob**

In `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/restart-cronjob.yaml`, add after `serviceAccountName: csi-addons-restart` in pod spec (line 67):

```yaml
          serviceAccountName: csi-addons-restart
          automountServiceAccountToken: true
```

- [ ] **Step 6: Add field to csi-addons-controller-manager deployment**

In `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml`, `serviceAccountName: csi-addons-controller-manager` is at line 93 (after containers, near end of pod spec). Add `automountServiceAccountToken: true` after it:

```yaml
      serviceAccountName: csi-addons-controller-manager
      automountServiceAccountToken: true
      terminationGracePeriodSeconds: 10
```

- [ ] **Step 7: Add field to snapshot-controller deployment**

In `cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml`, pod spec at line 35. Add after `serviceAccountName`:

```yaml
    spec:
      serviceAccountName: snapshot-controller
      automountServiceAccountToken: true
      containers:
```

- [ ] **Step 8: Verify YAML syntax**

Run:

```bash
yamllint \
  cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml \
  cluster/apps/github-system/github-token-rotation/app/cronjob.yaml \
  cluster/apps/github-system/bot-ssh-key-rotation/app/cronjob.yaml \
  cluster/apps/coder-workspaces/ssh-key-rotation/app/cronjob.yaml \
  cluster/apps/csi-addons-system/csi-addons-controller-manager/app/restart-cronjob.yaml \
  cluster/apps/csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml \
  cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml
```

Expected: no errors (warnings acceptable)

- [ ] **Step 9: Commit**

```bash
git add cluster/apps/authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml \
  cluster/apps/github-system/github-token-rotation/app/cronjob.yaml \
  cluster/apps/github-system/bot-ssh-key-rotation/app/cronjob.yaml \
  cluster/apps/coder-workspaces/ssh-key-rotation/app/cronjob.yaml \
  cluster/apps/csi-addons-system/csi-addons-controller-manager/app/restart-cronjob.yaml \
  cluster/apps/csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml \
  cluster/apps/kube-system/snapshot-controller/app/setup-snapshot-controller.yaml
git commit -m "feat(security): add explicit automountServiceAccountToken: true to API-using workloads

Ref #576"
```

______________________________________________________________________

### Task 2: Raw Manifests — Add `automountServiceAccountToken: false`

**Files:**

- Modify: `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml:19` (pod spec)

Note: `etcd-defrag` already has the field set (verified in codebase grep). Only `nexus-provision-repos` needs the pod-spec-level field (it has it at SA level via `provision-repos-rbac.yaml` but the validate policy checks pod spec).

- [ ] **Step 1: Add field to nexus-provision-repos job**

In `cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml`, add `automountServiceAccountToken: false` to pod spec after `serviceAccountName`:

```yaml
      serviceAccountName: nexus-provisioner
      automountServiceAccountToken: false
      restartPolicy: OnFailure
```

- [ ] **Step 2: Verify YAML syntax**

Run: `yamllint cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml`

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/nexus-system/nexus/app/provision-repos-job.yaml
git commit -m "feat(security): add explicit automountServiceAccountToken: false to nexus provisioner

Ref #576"
```

______________________________________________________________________

### Task 3: HelmRelease SA Hardening — Authentik

**Files:**

- Modify: `cluster/apps/authentik-system/authentik/app/values.yaml:206` (server section)
- Modify: `cluster/apps/authentik-system/authentik/app/release.yaml` (add postRenderer)

The authentik server Deployment currently uses the `default` SA because `server.serviceAccountName` is unset. The worker already uses the chart-created `authentik` SA. Fix: set server to reuse `authentik` SA, then patch both to disable automount (neither needs API access).

- [ ] **Step 1: Set server.serviceAccountName in values**

In `cluster/apps/authentik-system/authentik/app/values.yaml`, add `serviceAccountName: authentik` to the `server:` section (around line 206):

```yaml
server:
  serviceAccountName: authentik
  replicas: 1
```

- [ ] **Step 2: Add postRenderer to release.yaml**

In `cluster/apps/authentik-system/authentik/app/release.yaml`, append a `postRenderers` block after the existing `valuesFrom` section (the file currently has no postRenderers):

```yaml
  postRenderers:
    - kustomize:
        patches:
          - target:
              kind: Deployment
              name: authentik-server
            patch: |
              - op: add
                path: /spec/template/spec/automountServiceAccountToken
                value: false
          - target:
              kind: Deployment
              name: authentik-worker
            patch: |
              - op: add
                path: /spec/template/spec/automountServiceAccountToken
                value: false
```

- [ ] **Step 3: Verify YAML syntax**

Run: `yamllint cluster/apps/authentik-system/authentik/app/values.yaml cluster/apps/authentik-system/authentik/app/release.yaml`

Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/authentik-system/authentik/app/values.yaml \
  cluster/apps/authentik-system/authentik/app/release.yaml
git commit -m "feat(security): harden authentik SA — disable automount on server+worker

Server now uses chart-created 'authentik' SA instead of default.
Both deployments get automountServiceAccountToken: false via postRenderer.

Ref #576"
```

______________________________________________________________________

### Task 4: HelmRelease SA Hardening — Firefly III

**Files:**

- Modify: `cluster/apps/firefly-iii/firefly-iii/app/release.yaml:23` (add to existing postRenderers patches)

The firefly-iii chart has no SA configuration. Deployment and CronJob use `default` SA. Add automount patches to existing postRenderers.

- [ ] **Step 1: Add automount patches to existing postRenderers**

In `cluster/apps/firefly-iii/firefly-iii/app/release.yaml`, the `postRenderers[0].kustomize.patches` array already exists. Add two new patches to the end of the array:

```yaml
          - target:
              kind: Deployment
              name: firefly-iii
            patch: |
              - op: add
                path: /spec/template/spec/automountServiceAccountToken
                value: false
          - target:
              kind: CronJob
              name: firefly-iii-cronjob
            patch: |
              - op: add
                path: /spec/jobTemplate/spec/template/spec/automountServiceAccountToken
                value: false
```

- [ ] **Step 2: Verify YAML syntax**

Run: `yamllint cluster/apps/firefly-iii/firefly-iii/app/release.yaml`

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/firefly-iii/firefly-iii/app/release.yaml
git commit -m "feat(security): disable SA automount on firefly-iii deployment+cronjob

Ref #576"
```

______________________________________________________________________

### Task 5: HelmRelease SA Hardening — Victoria Logs & Traces

**Files:**

- Modify: `cluster/apps/observability/victoria-logs-single/app/values.yaml:1`
- Modify: `cluster/apps/observability/victoria-traces-single/app/values.yaml:1`

Both charts support `serviceAccount.create` and `serviceAccount.automountToken` values keys. Neither needs API access.

- [ ] **Step 1: Add serviceAccount config to victoria-logs-single values**

In `cluster/apps/observability/victoria-logs-single/app/values.yaml`, a commented-out `#serviceAccount:` block exists at lines 28-40. Replace that commented block with actual config:

```yaml
serviceAccount:
  create: true
  automountToken: false
```

- [ ] **Step 2: Add serviceAccount config to victoria-traces-single values**

In `cluster/apps/observability/victoria-traces-single/app/values.yaml`, add before the existing `server:` key:

```yaml
serviceAccount:
  create: true
  automountToken: false

server:
```

- [ ] **Step 3: Verify YAML syntax**

Run: `yamllint cluster/apps/observability/victoria-logs-single/app/values.yaml cluster/apps/observability/victoria-traces-single/app/values.yaml`

Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/observability/victoria-logs-single/app/values.yaml \
  cluster/apps/observability/victoria-traces-single/app/values.yaml
git commit -m "feat(security): create dedicated SAs with automount disabled for vlogs+vtraces

Ref #576"
```

______________________________________________________________________

### Task 6: HelmRelease Audit — Verify All Charts Set The Field

**Files:** Various values.yaml and release.yaml across the cluster

This is the investigation step. For each HelmRelease in the spec's "Verify Explicit automountServiceAccountToken" table, check if pods already have the field set. Fix any that don't via values or postRenderer.

- [ ] **Step 1: Get all pods missing automountServiceAccountToken**

Run:

```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.automountServiceAccountToken == null) | "\(.metadata.namespace)/\(.metadata.name)"' | sort
```

This identifies every running pod without an explicit field. Cross-reference with the table in the spec.

- [ ] **Step 2: For each pod missing the field, determine fix method**

For each namespace/pod from step 1:

1. Identify the owning HelmRelease
1. Check if the chart exposes a values key (search chart's values.yaml via Context7 or raw.githubusercontent.com)
1. If chart has a values key → set it in the app's values.yaml
1. If chart does NOT expose a values key → add postRenderer patch to the release.yaml

Common values keys by chart:

- Most charts: `serviceAccount.automountToken: false` or `automountServiceAccountToken: false`

- Traefik: `serviceAccount.automountServiceAccountToken: false` (verify upstream)

- Cilium: `serviceAccount.automount: true` (verify upstream)

- [ ] **Step 3: Apply fixes for all identified gaps**

For each gap found in step 2, apply the appropriate fix. Group changes by namespace for cleaner commits.

Example postRenderer patch for a Deployment (template for charts without values key):

```yaml
postRenderers:
  - kustomize:
      patches:
        - target:
            kind: Deployment
            name: <release-name>
          patch: |
            - op: add
              path: /spec/template/spec/automountServiceAccountToken
              value: false
```

Example postRenderer patch for a DaemonSet:

```yaml
        - target:
            kind: DaemonSet
            name: <release-name>
          patch: |
            - op: add
              path: /spec/template/spec/automountServiceAccountToken
              value: false
```

- [ ] **Step 4: Verify YAML syntax on all modified files**

Run yamllint on every file touched in this step.

- [ ] **Step 5: Commit**

```bash
git add <all modified values.yaml and release.yaml files>
git commit -m "feat(security): set explicit automountServiceAccountToken on all HelmRelease workloads

Ref #576"
```

______________________________________________________________________

### Task 7: Kyverno Mutate Policy — Authentik Outpost Exceptions

**Files:**

- Create: `cluster/apps/kyverno/policies/app/inject-automount-false-exceptions.yaml`

Deploy mutate BEFORE validate — mutate fires before validate in admission pipeline. Authentik outpost pods are created by the Authentik controller and we cannot modify their specs.

- [ ] **Step 1: Verify Authentik outpost label**

Run:

```bash
kubectl get pods -l app.kubernetes.io/managed-by=goauthentik.io --all-namespaces -o wide
```

Expected: returns one or more outpost pods. If label is different, adjust the policy match accordingly.

- [ ] **Step 2: Create mutate policy**

Create `cluster/apps/kyverno/policies/app/inject-automount-false-exceptions.yaml`:

```yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-automount-false-exceptions
  annotations:
    policies.kyverno.io/title: Inject automountServiceAccountToken for Uncontrollable Workloads
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: low
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Injects automountServiceAccountToken: false on pods created by controllers
      we cannot configure (Authentik outposts). Ensures they pass the
      require-explicit-automount validation policy.
spec:
  background: false
  rules:
    - name: inject-automount-authentik-outposts
      match:
        any:
          - resources:
              kinds:
                - Pod
              operations:
                - CREATE
      preconditions:
        all:
          - key: "{{request.object.metadata.labels.\"app.kubernetes.io/managed-by\" || ''}}"
            operator: Equals
            value: goauthentik.io
      mutate:
        patchStrategicMerge:
          spec:
            +(automountServiceAccountToken): false
```

- [ ] **Step 3: Verify YAML syntax**

Run: `yamllint cluster/apps/kyverno/policies/app/inject-automount-false-exceptions.yaml`

Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kyverno/policies/app/inject-automount-false-exceptions.yaml
git commit -m "feat(security): add Kyverno mutate policy for Authentik outpost automount injection

Ref #576"
```

______________________________________________________________________

### Task 8: Kyverno Validate Policy — Require Explicit Automount

**Files:**

- Create: `cluster/apps/kyverno/policies/app/require-explicit-automount.yaml`

This is the enforcement layer. Rejects any new pod that doesn't explicitly set `automountServiceAccountToken`.

- [ ] **Step 1: Create validate policy**

Create `cluster/apps/kyverno/policies/app/require-explicit-automount.yaml`:

```yaml
---
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-explicit-automount
  annotations:
    policies.kyverno.io/title: Require Explicit automountServiceAccountToken
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Requires all pods to explicitly declare automountServiceAccountToken
      (true or false). Forces authors to make a conscious decision about
      API token mounting.
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-automount-field
      match:
        any:
          - resources:
              kinds:
                - Pod
              operations:
                - CREATE
                - UPDATE
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kube-public
                - kube-node-lease
      validate:
        message: >-
          Pod {{request.object.metadata.name}} in namespace
          {{request.object.metadata.namespace}} must explicitly set
          spec.automountServiceAccountToken to true or false.
        deny:
          conditions:
            any:
              - key: "{{ request.object.spec.automountServiceAccountToken | type(@) }}"
                operator: NotEquals
                value: "boolean"
```

- [ ] **Step 2: Verify YAML syntax**

Run: `yamllint cluster/apps/kyverno/policies/app/require-explicit-automount.yaml`

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/require-explicit-automount.yaml
git commit -m "feat(security): add Kyverno validate policy requiring explicit automountServiceAccountToken

Rejects pods missing the field. Excludes kube-system, kube-public, kube-node-lease.

Ref #576"
```

______________________________________________________________________

### Task 9: Register Policies in Kustomization

**Files:**

- Modify: `cluster/apps/kyverno/policies/app/kustomization.yaml`

- [ ] **Step 1: Add new policy files to kustomization resources**

In `cluster/apps/kyverno/policies/app/kustomization.yaml`, append both new files to the existing `resources` list:

```yaml
  - ./inject-automount-false-exceptions.yaml
  - ./require-explicit-automount.yaml
```

- [ ] **Step 2: Verify YAML syntax**

Run: `yamllint cluster/apps/kyverno/policies/app/kustomization.yaml`

Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/kyverno/policies/app/kustomization.yaml
git commit -m "feat(security): register automount policies in kyverno kustomization

Ref #576"
```

______________________________________________________________________

### Task 10: Push, Verify, and Recreate Outpost Pods

**Files:** None (operational steps)

After all commits are pushed and Flux reconciles, verify the policies work and recreate Authentik outpost pods so mutate policy injects the field.

- [ ] **Step 1: Push all commits**

```bash
git push
```

Wait for Flux reconciliation (webhook-triggered).

- [ ] **Step 2: Verify policies are active**

```bash
kubectl get clusterpolicy require-explicit-automount -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
kubectl get clusterpolicy inject-automount-false-exceptions -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
```

Expected: both return `True`

- [ ] **Step 3: Delete existing Authentik outpost pods**

Authentik controller recreates them. Mutate policy injects `automountServiceAccountToken: false` on CREATE.

```bash
kubectl delete pod -l app.kubernetes.io/managed-by=goauthentik.io --all-namespaces
```

Wait ~30s for recreation.

- [ ] **Step 4: Verify outpost pods have the field**

```bash
kubectl get pods -l app.kubernetes.io/managed-by=goauthentik.io --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.spec.automountServiceAccountToken}{"\n"}{end}'
```

Expected: all show `false`

- [ ] **Step 5: Full audit — find any remaining pods without the field**

```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.automountServiceAccountToken == null) | "\(.metadata.namespace)/\(.metadata.name)"' | grep -v "^kube-system/" | grep -v "^kube-public/" | grep -v "^kube-node-lease/" | sort
```

Expected: empty output. If any pods appear, investigate and fix before closing the issue.

- [ ] **Step 6: Verify validate policy catches violations**

Dry-run a pod without the field to confirm rejection:

```bash
kubectl run test-automount --image=busybox --dry-run=server -o yaml 2>&1 | grep -i "automountServiceAccountToken"
```

Expected: admission error mentioning `must explicitly set spec.automountServiceAccountToken`

- [ ] **Step 7: Clean up test**

```bash
kubectl delete pod test-automount --ignore-not-found
```

______________________________________________________________________

## Rollout Order Summary

| Order | What                          | Why                                                    |
| ----- | ----------------------------- | ------------------------------------------------------ |
| 1     | Tasks 1-6 (Layer 1 + Layer 4) | Fix all existing workloads first                       |
| 2     | Task 7 (Layer 3 mutate)       | Inject field on uncontrollable pods before enforcement |
| 3     | Tasks 8-9 (Layer 2 validate)  | Enforce after all pods comply                          |
| 4     | Task 10 (verification)        | Recreate outpost pods, audit                           |

All tasks 1-9 can be committed together and pushed in one batch. The mutate policy fires before validate in the admission pipeline, so simultaneous deployment is safe. Existing outpost pods won't have the field until recreated (Task 10 step 3).
