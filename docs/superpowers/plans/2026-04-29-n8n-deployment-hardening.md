# n8n Deployment Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden n8n deployment for scaling — fix resource specs, deploy external task runners, enable PgBouncer connection pooling, remove deprecated config, complete VPA coverage.

**Architecture:** Single branch touching 7 files in `cluster/apps/n8n-system/n8n/app/`. Changes are pure GitOps config (Helm values, HelmRelease postRenderers, VPA, kustomization, CNPs). External task runners injected as sidecar via kustomize strategic merge (chart lacks `extraContainers`). PgBouncer poolers are already defined in a dormant file — we uncomment and point n8n at pooler service.
Existing CNPs already cover pooler data plane via shared `cnpg.io/cluster` label; only a metrics CNP is new.

**Tech Stack:** FluxCD HelmRelease, CNPG PgBouncer Pooler, Kubernetes VPA, Cilium CNPs

**Issue:** #1130

______________________________________________________________________

## File Map

| File                                                           | Action | Responsibility                                        |
| -------------------------------------------------------------- | ------ | ----------------------------------------------------- |
| `cluster/apps/n8n-system/n8n/app/values.yaml`                  | Modify | Resources, env vars, volumes, securityContext         |
| `cluster/apps/n8n-system/n8n/app/release.yaml`                 | Modify | postRenderers for runner sidecar                      |
| `cluster/apps/n8n-system/n8n/app/vpa.yaml`                     | Modify | Fix worker VPA, add webhook VPA, task-runner policies |
| `cluster/apps/n8n-system/n8n/app/kustomization.yaml`           | Modify | Uncomment poolers, add runner secret                  |
| `cluster/apps/n8n-system/n8n/app/n8n-cnpg-poolers.yaml`        | Modify | Switch session → transaction mode                     |
| `cluster/apps/n8n-system/n8n/app/network-policies.yaml`        | Modify | Add pooler CNPs                                       |
| `cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml` | Create | Runner auth token (user encrypts)                     |

______________________________________________________________________

### Task 1: Remove deprecated env var and add /tmp emptyDir

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml:104-105` (remove N8N_RUNNERS_ENABLED)
- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml:140-177` (add tmp volumes)

**Context:** `N8N_RUNNERS_ENABLED` is deprecated in n8n 2.x — task runners are always enabled. `N8N_RUNNERS_MODE=internal` is NOT deprecated and is left in place here (Task 4 switches it to `external`). The `/tmp` emptyDir is needed because `readOnlyRootFilesystem: true` blocks n8n from creating `/tmp/n8nDataTableUploads`.

- [ ] **Step 1: Remove N8N_RUNNERS_ENABLED from extraEnv**

In `values.yaml`, delete lines 104-105 (the `N8N_RUNNERS_ENABLED` block only):

```yaml
# DELETE these 2 lines:
    N8N_RUNNERS_ENABLED:
      value: "true"
```

Keep `N8N_RUNNERS_MODE` — Task 4 changes it to `external`.

- [ ] **Step 2: Add tmp emptyDir to shared volumes**

In `values.yaml`, add a `tmp` volume to `extraVolumes` (anchor `&extraVolumes`) and `extraVolumeMounts` (anchor `&extraVolumeMounts`).

Add to `extraVolumeMounts` (after the `n8n-prompts` mount, before the closing of the list):

```yaml
    - name: tmp
      mountPath: /tmp
```

Add to `extraVolumes` (after the `n8n-prompts` volume):

```yaml
    - name: tmp
      emptyDir: {}
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/values.yaml
git commit -m "fix(n8n): remove deprecated N8N_RUNNERS_ENABLED and add /tmp emptyDir

Remove N8N_RUNNERS_ENABLED (always enabled in 2.x) — generates
deprecation warnings on all pods. Keep N8N_RUNNERS_MODE=internal
(not deprecated, switched to external in Task 4).

Add emptyDir at /tmp for readOnlyRootFilesystem compatibility —
n8n needs /tmp/n8nDataTableUploads for data table uploads.

Ref #1130"
```

______________________________________________________________________

### Task 2: Fix worker and webhook resource specs

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml:208-228` (worker + webhook sections)

**Context:**

- Worker requests `cpu: 15m, memory: 64Mi` but actually uses 17m CPU / 227Mi memory. VPA recommends target `cpu: 35m, memory: 600Mi`, upper bound `cpu: 128m, memory: 1.1Gi`. No limits set.

- Webhook has zero resource specs. Currently uses 3m CPU / 176Mi memory.

- Set resources based on VPA recommendations with headroom.

- [ ] **Step 1: Set worker resources and concurrency**

In `values.yaml`, replace the worker resources block and add explicit concurrency:

```yaml
# BEFORE (lines 216-219):
  resources:
    requests:
      cpu: 15m
      memory: 64Mi

# AFTER:
  concurrency: 10
  resources:
    limits:
      cpu: 500m
      memory: 1.5Gi
    requests:
      cpu: 50m
      memory: 512Mi
```

Rationale: VPA target 35m/600Mi, upper 128m/1.1Gi. Requests at ~1.5x target, limits at ~4x target for CPU and ~1.4x VPA upper bound for memory headroom.

`concurrency: 10` sets `--concurrency 10` on the worker process. n8n defaults to 5 and warns when concurrency < 5 ("THIS CAN LEAD TO AN UNSTABLE ENVIRONMENT"). Setting 10 gives headroom above the warning threshold while matching production concurrency needs.

- [ ] **Step 2: Add webhook resources**

In `values.yaml`, add resources to the webhook section. Currently webhook section (lines 220-228) has no resources key. Add after `livenessProbe`:

```yaml
webhook:
  enabled: true
  extraEnv: *extraEnv
  extraVolumeMounts: *extraVolumeMounts
  extraVolumes: *extraVolumes
  deploymentAnnotations: *deploymentAnnotations
  readinessProbe: *readinessProbe
  livenessProbe: *livenessProbe
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 25m
      memory: 256Mi
```

Rationale: Webhook is lower resource than worker (3m/176Mi actual). Requests give 2x headroom on memory.

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/values.yaml
git commit -m "fix(n8n): set proper resource specs for worker and webhook

Worker was dangerously underprovisioned (15m/64Mi request vs 17m/227Mi
actual). Set to 50m/512Mi request, 500m/1.5Gi limit based on VPA recs.
Set explicit concurrency=10 (default 5 is at n8n warning threshold).

Webhook had zero resource specs. Set to 25m/256Mi request, 500m/512Mi
limit based on actual usage with headroom.

Ref #1130"
```

______________________________________________________________________

### Task 3: Add securityContext to worker and webhook

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml` (securityContext anchor + worker/webhook sections)

**Context:** Main pod has `readOnlyRootFilesystem: true` and drops all capabilities, but worker and webhook have empty `securityContext: {}` (chart default) — writable root filesystem, no capability restrictions. All 3 pods run the same n8n image with the same attack surface, so security posture should be identical. Anchor the securityContext and reference it from worker/webhook.

This also makes the `/tmp` emptyDir from Task 1 required for all pods (not just main), since `readOnlyRootFilesystem: true` blocks `/tmp` writes.

- [ ] **Step 1: Anchor main's securityContext**

In `values.yaml`, add `&securityContext` anchor to the existing securityContext block:

```yaml
# BEFORE:
  securityContext:
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000

# AFTER:
  securityContext: &securityContext
    capabilities:
      drop:
        - ALL
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    runAsUser: 1000
```

- [ ] **Step 2: Add securityContext to worker section**

In `values.yaml`, add `securityContext: *securityContext` to the worker section (after `deploymentAnnotations`):

```yaml
worker:
  enabled: true
  extraEnv: *extraEnv
  extraVolumeMounts: *extraVolumeMounts
  extraVolumes: *extraVolumes
  deploymentAnnotations: *deploymentAnnotations
  securityContext: *securityContext
  readinessProbe: *readinessProbe
  livenessProbe: *livenessProbe
```

- [ ] **Step 3: Add securityContext to webhook section**

In `values.yaml`, add `securityContext: *securityContext` to the webhook section (after `deploymentAnnotations`):

```yaml
webhook:
  enabled: true
  extraEnv: *extraEnv
  extraVolumeMounts: *extraVolumeMounts
  extraVolumes: *extraVolumes
  deploymentAnnotations: *deploymentAnnotations
  securityContext: *securityContext
  readinessProbe: *readinessProbe
  livenessProbe: *livenessProbe
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/values.yaml
git commit -m "fix(n8n): add securityContext to worker and webhook pods

Worker and webhook had empty securityContext — writable root filesystem
and no capability restrictions. Anchor main's securityContext and
reference from worker/webhook for consistent security posture.

All 3 pods now: readOnlyRootFilesystem, drop ALL capabilities,
runAsNonRoot, runAsUser 1000.

Ref #1130"
```

______________________________________________________________________

### Task 4: Deploy external task runners

**Files:**

- Create: `cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml` (user encrypts from template)
- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml` (env vars for external mode + Reloader)
- Modify: `cluster/apps/n8n-system/n8n/app/release.yaml` (postRenderers for runner sidecar)
- Modify: `cluster/apps/n8n-system/n8n/app/kustomization.yaml` (include new secret)

**Context:**

- Internal task runners execute Code node JS/Python in the same process as n8n — no isolation.
- External runners use a separate `n8nio/runners` sidecar container per pod, connected via broker on port 5679.
- Chart (8gears/n8n v2.0.1) has no `extraContainers` support — use Flux HelmRelease `postRenderers` to inject sidecar via kustomize strategic merge patch.
- Runner image version must match n8n version. Renovate grouping: repo-operator#128.
- All 3 pod types (main, worker, webhook) get the sidecar — in queue mode, workers execute production workflows and main handles manual executions. Webhook may not execute code but including it avoids crashes if `MODE=external` is set via shared `&extraEnv`.
- Sidecar uses localhost:5679 — no CNPs needed.

Do NOT set `N8N_CONCURRENCY_PRODUCTION_LIMIT` — in queue mode, this env var overrides `--concurrency` on workers. Since `&extraEnv` propagates to all pod types, it would conflict.

- [ ] **Step 1: Create SOPS template for runner auth token**

Create `cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml.tmpl`:

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: n8n-runner-secrets
  namespace: n8n-system
stringData:
  N8N_RUNNERS_AUTH_TOKEN: CHANGE_ME_GENERATE_RANDOM_TOKEN
```

User action: copy to `n8n-runner-secrets.sops.yaml`, replace placeholder with random token, encrypt with `sops -e -i`.

- [ ] **Step 2: Update kustomization.yaml to include runner secret**

In `kustomization.yaml`, add the SOPS secret to resources:

```yaml
# Add after n8n-secrets.sops.yaml:
  - ./n8n-runner-secrets.sops.yaml
```

- [ ] **Step 3: Update values.yaml — external runner env vars**

In `values.yaml`, replace the `N8N_RUNNERS_MODE` block and add broker/auth vars to `&extraEnv`:

```yaml
# BEFORE (after Task 1 removed N8N_RUNNERS_ENABLED):
    # Learn more: https://docs.n8n.io/hosting/configuration/task-runners/
    # TODO: migrate to external task runner
    N8N_RUNNERS_MODE:
      value: "internal"

# AFTER:
    # Learn more: https://docs.n8n.io/hosting/configuration/task-runners/
    N8N_RUNNERS_MODE:
      value: "external"
    N8N_RUNNERS_BROKER_LISTEN_ADDRESS:
      value: "0.0.0.0"
    N8N_RUNNERS_AUTH_TOKEN:
      valueFrom:
        secretKeyRef:
          name: n8n-runner-secrets
          key: N8N_RUNNERS_AUTH_TOKEN
    N8N_NATIVE_PYTHON_RUNNER:
      value: "true"
```

`N8N_NATIVE_PYTHON_RUNNER` enables Python Code node support — the `n8nio/runners` image ships with both JS and Python runners, but Python must be explicitly enabled on the n8n side.

Also update the Reloader annotation to watch the new secret:

```yaml
# BEFORE:
  deploymentAnnotations: &deploymentAnnotations
    secret.reloader.stakater.com/reload: "n8n-cnpg-cluster-app,n8n-secrets"

# AFTER:
  deploymentAnnotations: &deploymentAnnotations
    secret.reloader.stakater.com/reload: "n8n-cnpg-cluster-app,n8n-secrets,n8n-runner-secrets"
```

- [ ] **Step 4: Add postRenderers to release.yaml for runner sidecar**

In `release.yaml`, add `postRenderers` to inject the `n8nio/runners` sidecar into all Deployments rendered by the chart. Use `kustomize.images` for version management (Renovate-compatible):

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: n8n
spec:
  interval: 4h
  timeout: 15m
  chartRef:
    kind: OCIRepository
    name: n8n-ocirepo
    namespace: flux-system
  valuesFrom:
    - kind: ConfigMap
      name: n8n-values
  postRenderers:
    - kustomize:
        images:
          - name: n8nio/runners
            newTag: "2.16.2"
        patches:
          - target:
              kind: Deployment
            patch: |-
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: _
              spec:
                template:
                  spec:
                    volumes:
                      - name: runner-tmp
                        emptyDir: {}
                    containers:
                      - name: task-runner
                        image: n8nio/runners
                        env:
                          - name: N8N_RUNNERS_TASK_BROKER_URI
                            value: http://localhost:5679
                          - name: N8N_RUNNERS_AUTH_TOKEN
                            valueFrom:
                              secretKeyRef:
                                name: n8n-runner-secrets
                                key: N8N_RUNNERS_AUTH_TOKEN
                        volumeMounts:
                          - name: runner-tmp
                            mountPath: /tmp
                        securityContext:
                          capabilities:
                            drop:
                              - ALL
                          readOnlyRootFilesystem: true
                          runAsNonRoot: true
                          runAsUser: 1000
                        resources:
                          requests:
                            cpu: 10m
                            memory: 128Mi
                          limits:
                            cpu: 500m
                            memory: 512Mi
```

Notes:

- `kustomize.images` handles version pinning — Renovate's flux manager detects this natively.

- `target.kind: Deployment` applies to all 3 chart deployments (main, worker, webhook).

- Strategic merge adds `task-runner` container (new name = append, not replace).

- `metadata.name: _` is a placeholder — `target` handles resource selection.

- Runner uses localhost:5679 to reach the n8n broker process in the same pod.

- `readOnlyRootFilesystem: true` requires the `runner-tmp` emptyDir for code execution scratch space.

- Resource specs are initial estimates — VPA will refine after data collection.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/values.yaml \
      cluster/apps/n8n-system/n8n/app/release.yaml \
      cluster/apps/n8n-system/n8n/app/kustomization.yaml
git commit -m "feat(n8n): deploy external task runners as sidecar containers

Switch N8N_RUNNERS_MODE from internal to external. Inject n8nio/runners
sidecar into all deployments via HelmRelease postRenderers — chart lacks
extraContainers support.

External runners isolate Code node execution in a separate process.
Broker communicates over localhost:5679, no CNPs needed.

Runner image version managed via kustomize.images for Renovate
compatibility. Grouping rule: repo-operator#128.

SOPS secret for auth token created separately by user.

Ref #1130"
```

> **⛔ GATE: SOPS secret must exist before first push (Task 6a Step 5).** Kustomization now references `n8n-runner-secrets.sops.yaml`. If this file doesn't exist when pushed, Flux kustomize build fails. **Action:** User must create, encrypt, and commit the SOPS secret before proceeding past Task 5.
>
> ```bash
> cp cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml.tmpl \
>    cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml
> # Edit: replace CHANGE_ME_GENERATE_RANDOM_TOKEN with a random token
> sops -e -i cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml
> git add cluster/apps/n8n-system/n8n/app/n8n-runner-secrets.sops.yaml
> git commit -m "chore(n8n): add encrypted runner auth token secret
>
> Ref #1130"
> ```

______________________________________________________________________

### Task 5: Fix VPA specs

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/vpa.yaml`

**Context:**

- Worker VPA missing `maxAllowed` — add it matching new resource limits per repo pattern. VPA can't observe past the OOM boundary anyway, so `maxAllowed` = limits is the correct ceiling.

- No VPA for webhook deployment — pattern requires VPA for every workload.

- All 3 VPAs need a `task-runner` container policy for the sidecar injected in Task 4.

- Follow repo pattern: `updateMode: "Off"`, per-container policies, `minAllowed: cpu: 1m, memory: 1Mi`, `maxAllowed` = current resource limits.

- [ ] **Step 1: Add task-runner to main VPA and add maxAllowed to worker VPA**

In `vpa.yaml`, add `task-runner` container policy to the main (n8n) VPA:

```yaml
# BEFORE (main VPA containerPolicies):
      - containerName: n8n
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 2000m
          memory: 2048Mi

# AFTER:
      - containerName: n8n
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 2000m
          memory: 2048Mi
      - containerName: task-runner
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 500m
          memory: 512Mi
```

Add `maxAllowed` and `task-runner` to the worker VPA:

```yaml
# BEFORE (worker VPA containerPolicies):
      - containerName: n8n-worker
        minAllowed:
          cpu: 1m
          memory: 1Mi

# AFTER:
      - containerName: n8n-worker
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 500m
          memory: 1.5Gi
      - containerName: task-runner
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 500m
          memory: 512Mi
```

- [ ] **Step 2: Add webhook VPA**

Append to `vpa.yaml`:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: n8n-webhook
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: n8n-webhook
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: n8n-webhook
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 500m
          memory: 512Mi
      - containerName: task-runner
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 500m
          memory: 512Mi
```

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/vpa.yaml
git commit -m "fix(n8n): complete VPA coverage with task-runner sidecar

Add maxAllowed to worker VPA (was missing). Add webhook VPA (was
entirely missing). Add task-runner container policy to all 3 VPAs
for the external runner sidecar from Task 4.

Ref #1130"
```

______________________________________________________________________

### Task 6a: Deploy PgBouncer poolers and CNPs

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/kustomization.yaml:13-14` (uncomment poolers)
- Modify: `cluster/apps/n8n-system/n8n/app/n8n-cnpg-poolers.yaml` (session → transaction)
- Modify: `cluster/apps/n8n-system/n8n/app/network-policies.yaml` (add pooler metrics CNP)

**Context:**

- 3 n8n pods × `DB_POSTGRESDB_POOL_SIZE=10` = 30 direct connections to PostgreSQL.

- PgBouncer poolers already defined in `n8n-cnpg-poolers.yaml` but commented out in kustomization.

- Switch `poolMode: session` → `poolMode: transaction` — n8n uses TypeORM which doesn't use prepared statements, LISTEN/NOTIFY, or session state. Transaction mode multiplexes connections far better.

- Existing CNPs already cover pooler data plane traffic via broad `cnpg.io/cluster: n8n-cnpg-cluster` label selectors (pooler pods inherit this label). Only a metrics scraping CNP is genuinely new — PgBouncer exposes metrics on port 9127 vs CNPG's 9187.

- **Split into 6a/6b to avoid race condition:** pooler pods must be Running before n8n's DB host is switched to the pooler service.

- [ ] **Step 1: Switch pooler mode to transaction**

In `n8n-cnpg-poolers.yaml`, change both poolers from `session` to `transaction`:

```yaml
# Line 19 (rw pooler):
    poolMode: transaction

# Line 46 (ro pooler):
    poolMode: transaction
```

- [ ] **Step 2: Add PgBouncer pooler metrics CNP**

In `network-policies.yaml`, add one CNP for pooler metrics scraping. Add after the `allow-cnpg-internal-cluster` policy (before the `allow-claude-agent-ingress` policy).

Existing broad CNPs (`allow-cnpg-n8n-ingress`, `allow-cnpg-internal-cluster`) already cover pooler data plane on port 5432 via `cnpg.io/cluster` selector. Only the metrics port (9127) needs a new policy:

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# Allow metrics scraping from vmagent for PgBouncer pooler
# Data plane (port 5432) already covered by allow-cnpg-n8n-ingress and allow-cnpg-internal-cluster
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-pooler-metrics-ingress
spec:
  endpointSelector:
    matchLabels:
      cnpg.io/cluster: n8n-cnpg-cluster
      cnpg.io/podRole: pooler
  ingress:
    - fromEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: observability
            k8s:app.kubernetes.io/name: vmagent
      toPorts:
        - ports:
            - port: "9127"
              protocol: TCP
```

Note: CNPG pooler pods use label `cnpg.io/podRole: pooler` (NOT `role: pooler` — that label doesn't exist on pooler pods). PgBouncer metrics port is 9127 (CNPG source: `PgBouncerMetricsPort int32 = 9127`).

- [ ] **Step 3: Uncomment poolers in kustomization**

In `kustomization.yaml`, change lines 13-14:

```yaml
# BEFORE:
  # Dont need pooling yet, if pooling is needed when load increase can look at enabling.
  # - ./n8n-cnpg-poolers.yaml

# AFTER:
  - ./n8n-cnpg-poolers.yaml
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/kustomization.yaml \
      cluster/apps/n8n-system/n8n/app/n8n-cnpg-poolers.yaml \
      cluster/apps/n8n-system/n8n/app/network-policies.yaml
git commit -m "feat(n8n): deploy PgBouncer poolers with transaction mode

Enable CNPG PgBouncer poolers (rw + ro) with transaction pool mode.
n8n doesn't use prepared statements or session state, so transaction
mode gives better connection multiplexing than session mode.

Add metrics CNP for PgBouncer exporter port 9127. Data plane CNPs
already covered by existing cnpg.io/cluster label selectors.

DB host still points at direct CNPG — switch in next commit after
pooler pods are confirmed Running.

Ref #1130"
```

- [ ] **Step 5: Push and verify pooler pods are Running**

```bash
git push
```

Wait for Flux reconciliation, then verify:

```bash
kubectl get pods -n n8n-system -l cnpg.io/podRole=pooler
```

Expected: 2 pooler pods (rw + ro), Running state. Do NOT proceed to Task 6b until both are Ready.

______________________________________________________________________

### Task 6b: Switch n8n DB host to pooler service

**Files:**

- Modify: `cluster/apps/n8n-system/n8n/app/values.yaml` (DB host → pooler service)

**Context:** Pooler pods confirmed Running from Task 6a. Now safe to redirect n8n's DB connections through PgBouncer. CNPG Pooler creates a service matching the Pooler resource name (`n8n-cnpg-cluster-pooler-rw`). SSL still works — PgBouncer uses certs signed by the same cluster CA mounted at `DB_POSTGRESDB_SSL_CA_FILE`.

Also reduce `DB_POSTGRESDB_POOL_SIZE` from 10 to 5 per pod. With PgBouncer in transaction mode handling multiplexing, 5 client-side connections per pod (15 total) is sufficient — PgBouncer's `default_pool_size` (20) handles the actual PostgreSQL connection count.

- [ ] **Step 1: Point DB host at pooler service and reduce pool size**

In `values.yaml`, change `DB_POSTGRESDB_HOST` from secretKeyRef to hardcoded pooler service:

```yaml
# BEFORE:
    DB_POSTGRESDB_HOST:
      valueFrom:
        secretKeyRef:
          name: n8n-cnpg-cluster-app
          key: host

# AFTER:
    DB_POSTGRESDB_HOST:
      value: n8n-cnpg-cluster-pooler-rw.n8n-system.svc
```

Also reduce client-side pool size (PgBouncer handles multiplexing now):

```yaml
# BEFORE:
    DB_POSTGRESDB_POOL_SIZE:
      value: "10"

# AFTER:
    DB_POSTGRESDB_POOL_SIZE:
      value: "5"
```

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/n8n-system/n8n/app/values.yaml
git commit -m "feat(n8n): switch DB connections to PgBouncer pooler

Point DB_POSTGRESDB_HOST at pooler service instead of direct CNPG.
Reduce DB_POSTGRESDB_POOL_SIZE from 10 to 5 per pod — PgBouncer
handles connection multiplexing in transaction mode, so client-side
pool can be smaller.

Pooler pods confirmed Running in previous deploy.

Ref #1130"
```

Note: Push deferred to Task 7 — all remaining changes ship together.

______________________________________________________________________

### Task 7: Post-deploy verification

**Context:** After final push, cluster-validator runs automatically. Additional manual checks needed for pooler, TLS, and resource changes.

- [ ] **Step 1: Push to main**

```bash
git push
```

- [ ] **Step 2: Run cluster-validator (automated)**

Cluster-validator triggers after push.

- [ ] **Step 3: Verify n8n connects through pooler (no TLS errors)**

Check n8n main pod logs for successful DB connection and no TLS/SSL errors:

```bash
kubectl logs -n n8n-system -l app.kubernetes.io/name=n8n,app.kubernetes.io/type=master --tail=50
```

Look for: successful startup, no DB connection errors, no TLS hostname verification failures. PgBouncer uses certs signed by the same cluster CA, so CA verification works. node-postgres validates the certificate chain but doesn't verify hostname by default, so this should pass.

- [ ] **Step 4: Verify resource specs applied**

```bash
kubectl get deploy -n n8n-system -o custom-columns='NAME:.metadata.name,CPU_REQ:.spec.template.spec.containers[0].resources.requests.cpu,MEM_REQ:.spec.template.spec.containers[0].resources.requests.memory,CPU_LIM:.spec.template.spec.containers[0].resources.limits.cpu,MEM_LIM:.spec.template.spec.containers[0].resources.limits.memory'
```

Expected:

- n8n: 100m / 512Mi / 2000m / 2048Mi

- n8n-worker: 50m / 512Mi / 500m / 1.5Gi

- n8n-webhook: 25m / 256Mi / 500m / 512Mi

- [ ] **Step 5: Verify deprecation warnings gone**

```bash
kubectl logs -n n8n-system -l app.kubernetes.io/name=n8n --tail=100 | grep -i "N8N_RUNNERS_ENABLED\|deprecated"
```

Expected: No deprecation warnings for N8N_RUNNERS_ENABLED. N8N_RUNNERS_MODE may still appear in logs (not deprecated, intentionally kept).

- [ ] **Step 6: Verify external task runner sidecar**

Check all 3 pods have 2 containers (n8n + task-runner) and both are Running:

```bash
kubectl get pods -n n8n-system -l app.kubernetes.io/name=n8n -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.status.containerStatuses[*].name'
```

Expected: Each pod shows `n8n,task-runner` (or `n8n-worker,task-runner` / `n8n-webhook,task-runner`) with both ready.

Check runner sidecar logs for successful broker connection:

```bash
kubectl logs -n n8n-system -l app.kubernetes.io/name=n8n,app.kubernetes.io/type=master -c task-runner --tail=20
```

Look for: launcher startup, successful connection to broker at localhost:5679, no auth errors.

- [ ] **Step 7: Verify VPA recommendations (including task-runner)**

```bash
kubectl get vpa -n n8n-system -o custom-columns='NAME:.metadata.name,MODE:.spec.updatePolicy.updateMode,CONTAINERS:.status.recommendation.containerRecommendations[*].containerName'
```

Expected: 3 VPAs (n8n, n8n-worker, n8n-webhook), all mode "Off". Each should list both the main container and `task-runner`.

- [ ] **Step 8: Check SSL CA whitespace warning**

```bash
kubectl logs -n n8n-system -l app.kubernetes.io/name=n8n --tail=100 | grep -i "whitespace"
```

This warning is cosmetic — CNPG auto-generates the CA cert with standard PEM formatting that includes trailing newline. n8n 2.16.x added strict whitespace checking. Not actionable without patching the CNPG secret, which is auto-managed. Note in issue comment.

- [ ] **Step 9: Revisit webhook resources after VPA collects data**

Webhook resource specs (25m/256Mi) are based on `kubectl top` snapshot, not VPA recommendations (webhook VPA was just created in Task 5). After 24-48 hours, check VPA recommendations and adjust if needed:

```bash
kubectl get vpa n8n-webhook -n n8n-system -o jsonpath='{.status.recommendation.containerRecommendations[0]}' | jq .
```

______________________________________________________________________

## Items NOT in this plan (documented in issue)

| Item                       | Why deferred                                                                                         |
| -------------------------- | ---------------------------------------------------------------------------------------------------- |
| Deactivate broken workflow | Manual n8n UI action, not GitOps                                                                     |
| CNPG storage expansion     | Monitor first, expand when needed                                                                    |
| SSL CA whitespace          | Cosmetic warning from CNPG auto-generated cert, fixable with init container but not worth complexity |
| Renovate image grouping    | repo-operator#128 — separate repo                                                                    |
