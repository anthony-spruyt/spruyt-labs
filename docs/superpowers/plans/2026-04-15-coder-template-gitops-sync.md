# Coder Template GitOps Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automate `coder templates push` via Flux-reconciled Job so template edits under `coder/templates/**` sync to Coder on merge to `main`, with a weekly CronJob rotating the bot's session token.

**Architecture:**
Two workloads in a new `coder-template-sync` Kustomization:
(1) a hash-triggered Job (via `configMapGenerator`) that iterates `/templates/*/` and runs `coder templates push`;
(2) a weekly CronJob that self-renews the `gitops-bot` token and patches its Secret.
Bootstrap Secret uses `ssa: IfNotPresent` so Flux seeds once and runtime rotation is left alone.
All pods run restricted PSA, drop ALL caps, RORFS.
Image `ghcr.io/anthony-spruyt/coder-gitops:<v>` (built under [container-images#458](https://github.com/anthony-spruyt/container-images/issues/458)) ships `coder` CLI + `kubectl` + helper scripts.

**Tech Stack:** Flux Kustomization, Kustomize `configMapGenerator`, Kubernetes Job/CronJob, SOPS (Age), Cilium NetworkPolicy, Coder OSS CLI, `ghcr.io/anthony-spruyt/coder-gitops`.

**Spec:** `docs/superpowers/specs/2026-04-15-coder-template-gitops-sync-design.md`

**Issue:** [anthony-spruyt/spruyt-labs#934](https://github.com/anthony-spruyt/spruyt-labs/issues/934)

---

## File Structure

New directory `cluster/apps/coder-system/coder-template-sync/`:

| File | Responsibility |
| ---- | -------------- |
| `ks.yaml` | Flux Kustomization; `dependsOn: [coder]`; `targetNamespace: coder-system` |
| `app/kustomization.yaml` | Aggregates app resources + `configMapGenerator` for `../../../../coder/templates` |
| `app/kustomizeconfig.yaml` | Rewrites Job `volumes[*].configMap.name` to hashed ConfigMap name |
| `app/rbac.yaml` | Two ServiceAccounts + Role + RoleBinding (patch one Secret) |
| `app/secret-bootstrap.sops.yaml` | SOPS-encrypted initial token; `ssa: IfNotPresent` |
| `app/job-template-push.yaml` | Hash-triggered Job running `/usr/local/bin/push-templates.sh` |
| `app/cronjob-token-rotation.yaml` | Weekly CronJob running `/usr/local/bin/rotate-token.sh` |
| `app/network-policy.yaml` | CiliumNetworkPolicy egress (DNS, kube-apiserver, Coder svc) |
| `app/vpa.yaml` | VPA recommendations for Job + CronJob |

Existing files modified:

| File | Change |
| ---- | ------ |
| `cluster/apps/coder-system/kustomization.yaml` | Add `./coder-template-sync` |
| `cluster/apps/coder-system/coder/app/values.yaml` | Add `CODER_MAX_TOKEN_LIFETIME=8760h` env var |

---

## Task 0: Prerequisites (manual, tracked)

**User-driven; this task is a checklist, not code. Do not proceed past Task 3 without all items done.**

- [ ] **Step 1:** Confirm `ghcr.io/anthony-spruyt/coder-gitops:<v>` has been published via [container-images#458](https://github.com/anthony-spruyt/container-images/issues/458). Record the resolved tag (e.g. `1.0.0@sha256:...`) for use in Task 6.
- [ ] **Step 2:** Bump max token lifetime by adding env var to Coder server. Done in Task 1 below (code change, not manual).
- [ ] **Step 3:** After Task 1 is deployed, create the headless Coder user and initial token. Run from a shell with `coder` CLI logged in as an owner:

  ```bash
  coder users create \
    --username gitops-bot \
    --email gitops-bot@${EXTERNAL_DOMAIN} \
    --login-type none

  # Assign template-admin role (site-wide)
  coder organizations members edit-roles gitops-bot template-admin

  # Mint 720h bootstrap token
  coder tokens create --user gitops-bot --name bootstrap --lifetime 720h
  # Copy the printed token value
  ```

- [ ] **Step 4:** SOPS-seal the token into `app/secret-bootstrap.sops.yaml` (Task 4 creates the plaintext skeleton; user sops-encrypts via `sops -e -i`).

---

## Task 1: Bump `CODER_MAX_TOKEN_LIFETIME` on Coder server

**Files:**

- Modify: `cluster/apps/coder-system/coder/app/values.yaml`

- [ ] **Step 1: Add env var to values.yaml**

Edit `cluster/apps/coder-system/coder/app/values.yaml`, add under `coder.env:` (after `CODER_DERP_SERVER_STUN_ADDRESSES`):

```yaml
    - name: CODER_MAX_TOKEN_LIFETIME
      value: "8760h"
```

- [ ] **Step 2: Validate with qa-validator**

Invoke `qa-validator` agent. Expected: APPROVED.

- [ ] **Step 3: Commit and push**

```bash
git add cluster/apps/coder-system/coder/app/values.yaml
git commit -m "feat(coder): bump CODER_MAX_TOKEN_LIFETIME to 8760h

Enables 720h session tokens for the gitops-bot automation user.

Ref #934"
git push
```

- [ ] **Step 4: Validate deploy with cluster-validator**

Expected: APPROVED; coder Deployment rolls, `kubectl -n coder-system get deploy coder -o json | jq '.spec.template.spec.containers[0].env[] | select(.name==\"CODER_MAX_TOKEN_LIFETIME\").value'` prints `"8760h"`.

- [ ] **Step 5: Complete Task 0 Step 3 (manual)** — user creates headless user and bootstrap token now.

---

## Task 2: Scaffold directory + Flux Kustomization

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/ks.yaml`
- Create: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml` (placeholder; filled by later tasks)
- Modify: `cluster/apps/coder-system/kustomization.yaml`

- [ ] **Step 1: Create the placeholder `app/kustomization.yaml`**

File `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
```

- [ ] **Step 2: Create `ks.yaml`**

File `cluster/apps/coder-system/coder-template-sync/ks.yaml`:

```yaml
---
# yaml-language-server: $schema=https://k8s-schemas-cjso.pages.dev/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app coder-template-sync
  namespace: flux-system
spec:
  targetNamespace: coder-system
  path: ./cluster/apps/coder-system/coder-template-sync/app
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: coder
  prune: true
  timeout: 5m
  wait: false
```

(`wait: false` — Jobs are one-shot; Flux shouldn't block on completion.)

- [ ] **Step 3: Register the Kustomization**

Edit `cluster/apps/coder-system/kustomization.yaml`, add `./coder-template-sync` to `resources:`. Read the current file first and add the entry alphabetically.

- [ ] **Step 4: Validate + commit**

```bash
task dev-env:lint  # or rely on pre-commit
git add cluster/apps/coder-system/coder-template-sync/ \
        cluster/apps/coder-system/kustomization.yaml
git commit -m "feat(coder): scaffold coder-template-sync kustomization

Empty placeholder; resources added in subsequent commits.

Ref #934"
```

Do NOT push yet — wait until the Kustomization has at least one resource.

---

## Task 3: RBAC

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/rbac.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

- [ ] **Step 1: Create `rbac.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coder-template-sync
  namespace: coder-system
automountServiceAccountToken: false
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coder-token-rotation
  namespace: coder-system
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: coder-token-rotation
  namespace: coder-system
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["coder-gitops-bot-token"]
    verbs: ["get", "patch"]
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/rolebinding-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: coder-token-rotation
  namespace: coder-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: coder-token-rotation
subjects:
  - kind: ServiceAccount
    name: coder-token-rotation
    namespace: coder-system
```

Rationale: `coder-template-sync` SA does not need any RBAC (reads only mounted ConfigMap + Secret via pod spec, no API calls). Token is disabled (`automountServiceAccountToken: false`).

- [ ] **Step 2: Add to `app/kustomization.yaml`**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./rbac.yaml
```

- [ ] **Step 3: Validate**

Invoke `qa-validator`. Expected: APPROVED.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/rbac.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): add RBAC for coder-template-sync

Ref #934"
```

---

## Task 4: Bootstrap Secret (SOPS skeleton)

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/secret-bootstrap.sops.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

- [ ] **Step 1: Read `.sops.yaml` to confirm encryption rules cover the new file path**

```bash
Read .sops.yaml
```

All `cluster/apps/**/*.sops.yaml` are already covered by existing creation rules — no change needed.

- [ ] **Step 2: Create the plaintext skeleton**

File `cluster/apps/coder-system/coder-template-sync/app/secret-bootstrap.sops.yaml` (plaintext for now; user encrypts in Step 4):

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/secret-v1.json
apiVersion: v1
kind: Secret
metadata:
  name: coder-gitops-bot-token
  namespace: coder-system
  annotations:
    # Seed once; leave runtime rotation alone.
    kustomize.toolkit.fluxcd.io/ssa: IfNotPresent
type: Opaque
stringData:
  token: REPLACE_WITH_BOOTSTRAP_TOKEN
  token-id: REPLACE_WITH_BOOTSTRAP_TOKEN_ID
```

The `token-id` field holds the Coder token ID (UUID from `coder tokens list -o json`), used by rotation to revoke the old token cleanly.

- [ ] **Step 3: User fills real values**

User replaces the two placeholders with the real token value and ID from Task 0 Step 3. Obtain the ID via:

```bash
coder tokens list --user gitops-bot -o json | jq -r '.[] | select(.name=="bootstrap") | .id'
```

- [ ] **Step 4: User encrypts**

```bash
sops -e -i cluster/apps/coder-system/coder-template-sync/app/secret-bootstrap.sops.yaml
```

- [ ] **Step 5: Add to `app/kustomization.yaml`**

Update `resources:` to:

```yaml
resources:
  - ./rbac.yaml
  - ./secret-bootstrap.sops.yaml
```

- [ ] **Step 6: Validate**

Invoke `qa-validator`. Expected: APPROVED; no unencrypted Secret hook violations.

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/secret-bootstrap.sops.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): add bootstrap token secret for gitops-bot

Seeded via SOPS; ssa=IfNotPresent so rotation mutations persist.

Ref #934"
```

---

## Task 5: ConfigMap generator + kustomizeconfig

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/kustomizeconfig.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

- [ ] **Step 1: Create `kustomizeconfig.yaml`**

```yaml
---
nameReference:
  - kind: ConfigMap
    version: v1
    fieldSpecs:
      - path: spec/template/spec/volumes/configMap/name
        kind: Job
      - path: spec/jobTemplate/spec/template/spec/volumes/configMap/name
        kind: CronJob
```

- [ ] **Step 2: Extend `app/kustomization.yaml` with the generator**

Full updated file:

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./rbac.yaml
  - ./secret-bootstrap.sops.yaml
configMapGenerator:
  - name: coder-templates
    namespace: coder-system
    files:
      - templates/devcontainer/main.tf=../../../../../coder/templates/devcontainer/main.tf
      - templates/devcontainer/README.md=../../../../../coder/templates/devcontainer/README.md
configurations:
  - ./kustomizeconfig.yaml
```

Rationale: explicit file list (rather than a glob) keeps the hash deterministic and makes adding a new template a visible diff. Each template's files live under `templates/<name>/...` inside the ConfigMap so the Job script can iterate `/templates/*/`.

- [ ] **Step 3: Dry-run kustomize build**

```bash
kubectl kustomize cluster/apps/coder-system/coder-template-sync/app | \
  grep -E '^(kind|  name):' | head -40
```

Expected: a `ConfigMap` with name like `coder-templates-<hash>`.

- [ ] **Step 4: Validate**

Invoke `qa-validator`. Expected: APPROVED.

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/kustomizeconfig.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): generate hashed configmap from coder/templates

Ref #934"
```

---

## Task 6: Template-push Job

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/job-template-push.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

Uses image tag resolved in Task 0 Step 1. Substitute `<IMAGE_TAG>` below with the real pinned `tag@sha256:...`.

- [ ] **Step 1: Create `job-template-push.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/job-batch-v1.json
apiVersion: batch/v1
kind: Job
metadata:
  name: coder-template-push
  namespace: coder-system
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app: coder-template-push
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      serviceAccountName: coder-template-sync
      automountServiceAccountToken: false
      restartPolicy: Never
      containers:
        - name: push
          image: ghcr.io/anthony-spruyt/coder-gitops:<IMAGE_TAG>
          command: ["/usr/local/bin/push-templates.sh"]
          env:
            - name: CODER_URL
              value: "http://coder.coder-system.svc.cluster.local"
            - name: CODER_SESSION_TOKEN
              valueFrom:
                secretKeyRef:
                  name: coder-gitops-bot-token
                  key: token
            - name: HOME
              value: /tmp
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          volumeMounts:
            - name: templates
              mountPath: /templates
              readOnly: true
            - name: tmp
              mountPath: /tmp
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            capabilities:
              drop:
                - ALL
            seccompProfile:
              type: RuntimeDefault
      volumes:
        - name: templates
          configMap:
            name: coder-templates
        - name: tmp
          emptyDir:
            medium: Memory
            sizeLimit: 64Mi
```

Confirm internal service name/port: `kubectl -n coder-system get svc coder -o json | jq '.spec.ports'`. The Coder OSS Helm chart default is a ClusterIP service named `coder` exposing port 80 → container port 7080. If the port differs, adjust `CODER_URL` accordingly.

- [ ] **Step 2: Add to `app/kustomization.yaml`**

Append `./job-template-push.yaml` to `resources:`.

- [ ] **Step 3: Validate**

Invoke `qa-validator`. Expected: APPROVED; hash-suffix reference resolves.

- [ ] **Step 4: Commit (do not push yet)**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/job-template-push.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): add template-push job

Runs coder templates push for each template on ConfigMap hash change.

Ref #934"
```

---

## Task 7: Token-rotation CronJob

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/cronjob-token-rotation.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

- [ ] **Step 1: Create `cronjob-token-rotation.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/cronjob-batch-v1.json
apiVersion: batch/v1
kind: CronJob
metadata:
  name: coder-token-rotation
  namespace: coder-system
spec:
  schedule: "0 2 * * 0"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 86400
      template:
        metadata:
          labels:
            app: coder-token-rotation
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
            seccompProfile:
              type: RuntimeDefault
          serviceAccountName: coder-token-rotation
          restartPolicy: Never
          containers:
            - name: rotate
              image: ghcr.io/anthony-spruyt/coder-gitops:<IMAGE_TAG>
              command: ["/usr/local/bin/rotate-token.sh"]
              env:
                - name: CODER_URL
                  value: "http://coder.coder-system.svc.cluster.local"
                - name: CODER_SESSION_TOKEN
                  valueFrom:
                    secretKeyRef:
                      name: coder-gitops-bot-token
                      key: token
                - name: CODER_OLD_TOKEN_ID
                  valueFrom:
                    secretKeyRef:
                      name: coder-gitops-bot-token
                      key: token-id
                - name: SECRET_NAME
                  value: coder-gitops-bot-token
                - name: SECRET_NAMESPACE
                  value: coder-system
                - name: NEW_TOKEN_LIFETIME
                  value: "720h"
                - name: HOME
                  value: /tmp
              resources:
                requests:
                  cpu: 10m
                  memory: 64Mi
                limits:
                  cpu: 200m
                  memory: 256Mi
              volumeMounts:
                - name: tmp
                  mountPath: /tmp
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                runAsNonRoot: true
                runAsUser: 1000
                runAsGroup: 1000
                capabilities:
                  drop:
                    - ALL
                seccompProfile:
                  type: RuntimeDefault
          volumes:
            - name: tmp
              emptyDir:
                medium: Memory
                sizeLimit: 32Mi
```

Contract with `rotate-token.sh` (from container-images#458):

1. Log in using `$CODER_SESSION_TOKEN`.
2. Mint a new token with `--lifetime $NEW_TOKEN_LIFETIME --name gitops-bot-$(date -u +%Y%m%dT%H%M%SZ)`.
3. Capture new token value and new token ID.
4. `kubectl -n $SECRET_NAMESPACE patch secret $SECRET_NAME --type=merge -p "{\"stringData\":{\"token\":\"$NEW\",\"token-id\":\"$NEW_ID\"}}"`.
5. Revoke `$CODER_OLD_TOKEN_ID` via `coder tokens remove $CODER_OLD_TOKEN_ID` (continue on failure; log).
6. Exit 0 only if steps 1–4 succeeded.

- [ ] **Step 2: Add to `app/kustomization.yaml`**

Append `./cronjob-token-rotation.yaml` to `resources:`.

- [ ] **Step 3: Validate + commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/cronjob-token-rotation.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): add weekly token rotation cronjob

Ref #934"
```

---

## Task 8: NetworkPolicy

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/network-policy.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

- [ ] **Step 1: Read existing Cilium policies for pattern**

```bash
Read cluster/apps/coder-system/coder/app/network-policies.yaml
```

Match style (API version, egress-only, reserved entities).

- [ ] **Step 2: Create `network-policy.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/cilium.io/ciliumnetworkpolicy_v2.json
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: coder-template-sync-egress
  namespace: coder-system
spec:
  endpointSelector:
    matchExpressions:
      - key: app
        operator: In
        values:
          - coder-template-push
          - coder-token-rotation
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: UDP
            - port: "53"
              protocol: TCP
          rules:
            dns:
              - matchPattern: "*"
    - toEntities:
        - kube-apiserver
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            app.kubernetes.io/name: coder
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
```

Confirm the Coder pod's actual label selector via `kubectl -n coder-system get pods -l app.kubernetes.io/name=coder` (adjust if the chart uses different labels).

- [ ] **Step 3: Add to `app/kustomization.yaml`**

Append `./network-policy.yaml` to `resources:`.

- [ ] **Step 4: Validate + commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/network-policy.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): restrict template-sync egress via cilium policy

Ref #934"
```

---

## Task 9: VPA

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/app/vpa.yaml`
- Modify: `cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml`

Per repo pattern (`.claude/rules/patterns.md`), every workload needs a VPA in recommendation-only mode.

- [ ] **Step 1: Create `vpa.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: coder-template-push
  namespace: coder-system
spec:
  targetRef:
    apiVersion: batch/v1
    kind: Job
    name: coder-template-push
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: push
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 500m
          memory: 512Mi
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: coder-token-rotation
  namespace: coder-system
spec:
  targetRef:
    apiVersion: batch/v1
    kind: CronJob
    name: coder-token-rotation
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: rotate
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          cpu: 200m
          memory: 256Mi
```

- [ ] **Step 2: Append to `app/kustomization.yaml`**

Final `resources` list:

```yaml
resources:
  - ./rbac.yaml
  - ./secret-bootstrap.sops.yaml
  - ./job-template-push.yaml
  - ./cronjob-token-rotation.yaml
  - ./network-policy.yaml
  - ./vpa.yaml
```

- [ ] **Step 3: Validate + commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/app/vpa.yaml \
        cluster/apps/coder-system/coder-template-sync/app/kustomization.yaml
git commit -m "feat(coder): add vpa recommendations for template-sync workloads

Ref #934"
```

---

## Task 10: Renovate tracking for the new image

**Files:**

- Modify: `.github/renovate/groups.json5` (if a Coder-related group exists; otherwise skip)

- [ ] **Step 1: Read current renovate config**

```bash
Read .github/renovate/groups.json5
```

- [ ] **Step 2: Confirm `ghcr.io/anthony-spruyt/coder-gitops` will be matched by an existing rule**

Repo-wide container image rules already auto-detect `ghcr.io/...` tags in Kubernetes manifests. No change required unless a specific group is desired. If wanted, add to an existing rule — do NOT create a new file unless necessary.

- [ ] **Step 3: Commit only if changed** (otherwise skip the task).

---

## Task 11: Deploy and verify end-to-end

Full cluster-side verification after everything is committed.

- [ ] **Step 1: Push all commits**

```bash
git push
```

- [ ] **Step 2: Run `cluster-validator` agent**

Expected: APPROVED. Flux `coder-template-sync` Kustomization reconciles, ConfigMap/Secret/Job/CronJob/NetworkPolicy all present.

- [ ] **Step 3: Verify template-push Job completed successfully**

```bash
kubectl -n coder-system get jobs -l app=coder-template-push
kubectl -n coder-system logs job/coder-template-push-<hash>
```

Expected: job Status `Complete`, logs end with `push OK: devcontainer`.

- [ ] **Step 4: Verify template version bumped in Coder**

From a dev shell with coder CLI logged in as admin:

```bash
coder templates versions list devcontainer
```

Expected: a new version created within minutes of the merge.

- [ ] **Step 5: Create a workspace from the new template version**

Via UI or `coder create`. Expected: workspace admits cleanly under PSA=restricted (closes #932 pain point).

- [ ] **Step 6: Idempotence test**

Merge an unrelated change (e.g., docs). Expected: no new `coder-template-push` Job created (hash unchanged).

- [ ] **Step 7: Trigger rotation manually**

```bash
kubectl -n coder-system create job --from=cronjob/coder-token-rotation rotation-smoke-test
kubectl -n coder-system logs job/rotation-smoke-test
```

Expected: new token minted, Secret `resourceVersion` bumped, prior token revoked:

```bash
kubectl -n coder-system get secret coder-gitops-bot-token -o jsonpath='{.metadata.resourceVersion}'
# DO NOT print .data — that would leak the token
coder tokens list --user gitops-bot
# Expect: only the new token present; bootstrap token gone.
```

- [ ] **Step 8: Manual push still works (escape hatch)**

```bash
coder templates push devcontainer -y
```

Expected: succeeds, creates yet another version (proves the automation didn't break the manual path).

- [ ] **Step 9: Close the issue**

Ask user to confirm; once confirmed:

```bash
gh issue close 934 --repo anthony-spruyt/spruyt-labs \
  --comment "Delivered in <commit-sha-range>. See plan at docs/superpowers/plans/2026-04-15-coder-template-gitops-sync.md."
```

---

## Post-deploy operational notes

Add to runbook (optional follow-up task, not part of this plan's acceptance):

- **Token expired, rotation failed:** user re-mints token manually, updates `token` + `token-id` in the live Secret (or deletes Secret to let Flux re-seed from SOPS), triggers the CronJob manually.
- **Orphan token after partial rotation failure:** `coder tokens list --user gitops-bot` → identify stale tokens → `coder tokens remove <id>` each.
- **Adding a new template:** create directory under `coder/templates/<name>/`, add its files to the `configMapGenerator.files` list in `app/kustomization.yaml`, commit, push. Job runs automatically on merge.
