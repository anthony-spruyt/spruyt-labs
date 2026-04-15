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
| `ks.yaml` | Flux Kustomization; `dependsOn: [coder]`; `targetNamespace: coder-system`; `force: true` |
| `README.md` | Component docs (per `documentation.md` rule) |
| `app/kustomization.yaml` | Aggregates app resources + `configMapGenerator` reading `./templates/**` (in-tree — no path traversal) |
| `app/kustomizeconfig.yaml` | Rewrites Job/CronJob `volumes.configMap.name` to hashed ConfigMap name |
| `app/rbac.yaml` | Two ServiceAccounts + Role + RoleBinding (patch one Secret) |
| `app/secret-bootstrap.sops.yaml` | SOPS-encrypted initial token; `ssa: IfNotPresent` |
| `app/job-template-push.yaml` | Hash-triggered Job running `/usr/local/bin/push-templates.sh` |
| `app/cronjob-token-rotation.yaml` | Weekly CronJob running `/usr/local/bin/rotate-token.sh` |
| `app/network-policy.yaml` | CiliumNetworkPolicy egress (kube-apiserver, Coder svc); DNS is clusterwide already |
| `app/vpa.yaml` | VPA recommendations (Off mode) |
| `app/templates/devcontainer/main.tf` | Terraform template source (moved via `git mv` from `coder/templates/devcontainer/`) |
| `app/templates/devcontainer/README.md` | Template docs (moved) |
| `app/templates/devcontainer/.terraform.lock.hcl` | Provider lock (moved) |

Rationale for moving templates: Flux's kustomize-controller uses default `LoadRestrictionsRootOnly`, which forbids `configMapGenerator.files` paths that escape the kustomization root (`..`). Co-locating template sources with their sync manifests keeps paths local and makes the component self-contained.

Existing files modified:

| File | Change |
| ---- | ------ |
| `cluster/apps/coder-system/kustomization.yaml` | Add `./coder-template-sync` |
| `cluster/apps/coder-system/coder/app/values.yaml` | Add `CODER_MAX_TOKEN_LIFETIME=8760h` env var |
| `coder/templates/devcontainer/` | **Moved** via `git mv` to `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/`. The top-level `coder/` directory is removed if empty after the move. |

---

## Task 0: Prerequisites (manual, tracked)

**User-driven; this task is a checklist, not code. Do not proceed past Task 3 without all items done.**

- [x] **Step 1:** Image published: `ghcr.io/anthony-spruyt/coder-gitops:1.0.0@sha256:c28f9673fbdfce4755ac3b17033e9aa67b17b9ea78eaf641b4dcb2d7c945b1a1` (container-images#458 released).
- [ ] **Step 2:** Bump max token lifetime by adding env var to Coder server. Done in Task 1 below (code change, not manual).
- [ ] **Step 3:** After Task 1 is deployed, create the headless Coder user and initial token. Run from a shell with `coder` CLI logged in as an owner. **SECURITY: do NOT paste the resulting token into chat, logs, issues, or PRs. Move it directly into the SOPS file per Task 4.**

  ```bash
  coder users create \
    --username gitops-bot \
    --email gitops-bot@${EXTERNAL_DOMAIN} \
    --login-type none

  # Assign template-admin role (site-wide). Verify the role name for the running
  # Coder version first: `coder organizations members roles --help`. Current Coder
  # OSS uses `template-admin`; older versions may use `template_admin`.
  coder organizations members edit-roles gitops-bot template-admin

  # Mint 720h bootstrap token
  coder tokens create --user gitops-bot --name bootstrap --lifetime 720h
  # Token prints once. Pipe directly into a file with 0600 perms, then sops-encrypt.
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
  force: true   # delete+recreate immutable resources (Job spec is immutable; hash change => new Job)
  timeout: 5m
  wait: false
```

- `wait: false` — Jobs are one-shot; Flux shouldn't block on completion.
- `force: true` — when the `configMapGenerator` hash changes, the referenced Job's `spec.template.spec.volumes[].configMap.name` changes. Job `spec.template` is immutable post-create, so SSA apply would fail. `force: true` instructs kustomize-controller to delete+recreate the Job so the new hash binds to a fresh pod run. Documented pattern: <https://fluxcd.io/flux/components/kustomize/kustomizations/#controlling-the-apply-behavior-of-resources>.

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
automountServiceAccountToken: false
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/serviceaccount-v1.json
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coder-token-rotation
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/role-rbac-v1.json
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: coder-token-rotation
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
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: coder-token-rotation
subjects:
  - kind: ServiceAccount
    name: coder-token-rotation
```

(Per-resource `namespace:` omitted; `targetNamespace: coder-system` in `ks.yaml` + `commonMetadata` inject it — matches existing `coder/app/oauth-rotation-rbac.yaml` style.)

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

## Task 4b: Move template sources in-tree

**Files:**

- Remove: `coder/templates/devcontainer/` (entire tree)
- Create: `cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/` (same contents)

Rationale: Kustomize default `LoadRestrictionsRootOnly` (used by flux kustomize-controller) forbids `configMapGenerator.files` paths that escape the kustomization root. Co-locating template sources with the sync manifest removes path traversal and makes the component self-contained.

- [ ] **Step 1: Move the tree with `git mv`**

```bash
mkdir -p cluster/apps/coder-system/coder-template-sync/app/templates
git mv coder/templates/devcontainer \
       cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer

# Remove the terraform cache directory if it was tracked (it shouldn't be, but verify)
rm -rf cluster/apps/coder-system/coder-template-sync/app/templates/devcontainer/.terraform

# Remove now-empty parent if nothing else lives under coder/
rmdir coder/templates coder 2>/dev/null || true
```

- [ ] **Step 2: Add `.terraform/` to `.gitignore` if not already present**

Run `Grep(pattern="\.terraform/", path=".gitignore")`. If absent, append:

```gitignore
cluster/apps/coder-system/coder-template-sync/app/templates/**/.terraform/
cluster/apps/coder-system/coder-template-sync/app/templates/**/.terraform.tfstate*
```

- [ ] **Step 3: Update references**

```bash
Grep(pattern="coder/templates", path=".")
```

Update any doc/README/task references (README in `coder/`, `docs/**`, `.taskfiles/**`) to point at the new path. Do NOT change references inside `docs/superpowers/specs/` or this plan itself.

- [ ] **Step 4: Validate + commit**

```bash
git add -u coder/ cluster/apps/coder-system/coder-template-sync/app/templates/ .gitignore
# .gitignore add may need explicit: git add .gitignore
git commit -m "refactor(coder): move devcontainer template into coder-template-sync app

Required for GitOps configMapGenerator (kustomize default load
restrictions forbid path traversal).

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
    files:
      - templates/devcontainer/main.tf=./templates/devcontainer/main.tf
      - templates/devcontainer/README.md=./templates/devcontainer/README.md
      - templates/devcontainer/.terraform.lock.hcl=./templates/devcontainer/.terraform.lock.hcl
configurations:
  - ./kustomizeconfig.yaml
```

Rationale: explicit file list (rather than a glob) keeps the hash deterministic and makes adding a new template a visible diff. Each template's files live under `templates/<name>/...` inside the ConfigMap so the Job script can iterate `/templates/*/`.

- [ ] **Step 2a: ConfigMap size guard**

Kubernetes enforces a 1MiB (1,048,576 byte) limit on ConfigMap data. Verify:

```bash
du -sb cluster/apps/coder-system/coder-template-sync/app/templates | awk '{print $1}'
```

Expected: well under 900,000 bytes. If ever exceeded (future large template), switch strategy to a Flux `GitRepository` source + volume mount. Note the threshold in README.

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

Image tag: `ghcr.io/anthony-spruyt/coder-gitops:1.0.0@sha256:c28f9673fbdfce4755ac3b17033e9aa67b17b9ea78eaf641b4dcb2d7c945b1a1` (published via [container-images#458](https://github.com/anthony-spruyt/container-images/issues/458)).

- [ ] **Step 1: Create `job-template-push.yaml`**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/job-batch-v1.json
apiVersion: batch/v1
kind: Job
metadata:
  name: coder-template-push
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/name: coder-template-push
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
          image: ghcr.io/anthony-spruyt/coder-gitops:1.0.0@sha256:c28f9673fbdfce4755ac3b17033e9aa67b17b9ea78eaf641b4dcb2d7c945b1a1
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
              value: /home/coder
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
            - name: home
              mountPath: /home/coder
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
        - name: home
          emptyDir:
            medium: Memory
            sizeLimit: 32Mi
```

Confirmed: `kubectl -n coder-system get svc coder -o jsonpath='{.spec.ports}'` returns `port: 80` (the chart's ClusterIP front door). `CODER_URL=http://coder.coder-system.svc.cluster.local` resolves to that service.

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
            app.kubernetes.io/name: coder-token-rotation
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
            seccompProfile:
              type: RuntimeDefault
          serviceAccountName: coder-token-rotation
          automountServiceAccountToken: true   # required for kubectl apply to kube-apiserver
          restartPolicy: Never
          containers:
            - name: rotate
              image: ghcr.io/anthony-spruyt/coder-gitops:1.0.0@sha256:c28f9673fbdfce4755ac3b17033e9aa67b17b9ea78eaf641b4dcb2d7c945b1a1
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
                  value: /home/coder
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
                - name: home
                  mountPath: /home/coder
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
            - name: home
              emptyDir:
                medium: Memory
                sizeLimit: 32Mi
```

Contract with `rotate-token.sh` (from container-images#458):

1. Log in using `$CODER_SESSION_TOKEN`.
2. Mint a new token: `NEW=$(coder tokens create --lifetime "$NEW_TOKEN_LIFETIME" --name "gitops-bot-$(date -u +%Y%m%dT%H%M%SZ)")`.
3. Parse new token ID from `coder tokens list --output json | jq -r '.[-1].id'` (or from the create response if the CLI exposes it).
4. Write a fresh Secret manifest and apply it — **use `kubectl apply`, not `patch --type=merge`**, so `stringData` is handled correctly by the apiserver:

   ```bash
   cat <<EOF | kubectl -n "$SECRET_NAMESPACE" apply -f -
   apiVersion: v1
   kind: Secret
   metadata:
     name: $SECRET_NAME
     annotations:
       kustomize.toolkit.fluxcd.io/ssa: IfNotPresent
   type: Opaque
   stringData:
     token: $NEW
     token-id: $NEW_ID
   EOF
   ```

   The `IfNotPresent` annotation matches the manifest shipped by Flux so no drift is introduced.
5. Revoke the old token: `coder tokens remove "$CODER_OLD_TOKEN_ID"` (log failure, do not fail the job — the new token already works).
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
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cilium.io/ciliumnetworkpolicy_v2.json
# DNS egress already allowed clusterwide via `allow-kube-dns-egress`; only
# Coder + kube-apiserver are app-specific.
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: coder-template-sync-egress
spec:
  endpointSelector:
    matchExpressions:
      - key: app.kubernetes.io/name
        operator: In
        values:
          - coder-template-push
          - coder-token-rotation
  egress:
    # kube-apiserver for kubectl apply (rotation only; push has automount=false)
    - toEntities:
        - kube-apiserver
      toPorts:
        - ports:
            - port: "6443"
              protocol: TCP
    # Coder control plane for CLI calls
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: coder-system
            k8s:app.kubernetes.io/name: coder
      toPorts:
        - ports:
            - port: "80"
              protocol: TCP
```

Verified: the Coder pod carries `app.kubernetes.io/name: coder` (see existing `allow-cnpg-egress` and siblings in `coder/app/network-policies.yaml`). Service port 80 confirmed via `kubectl get svc coder -n coder-system -o jsonpath='{.spec.ports}'`.

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

## Task 9b: Component README

**Files:**

- Create: `cluster/apps/coder-system/coder-template-sync/README.md`

Per `.claude/rules/documentation.md`: "New app components require README.md before commit/merge."

- [ ] **Step 1: Read template**

```bash
Read docs/templates/readme_template.md
```

- [ ] **Step 2: Author README** covering:
  - Overview: hash-triggered Job pushes `coder/templates/**` to Coder via `gitops-bot` user; weekly CronJob rotates the session token.
  - Prerequisites: `coder` Kustomization deployed; `gitops-bot` user + bootstrap token seeded into `coder-gitops-bot-token` Secret.
  - Operation:
    - Add a new template: create dir under `app/templates/<name>/`, list files in `configMapGenerator.files`, commit.
    - Manual push (escape hatch): `coder templates push <name> -y` from a dev shell.
    - Manual rotation: `kubectl -n coder-system create job --from=cronjob/coder-token-rotation rotation-smoke-test`.
  - Troubleshooting: rotation failure, token expired (delete Secret → Flux re-seeds from SOPS → re-run), ConfigMap >1MiB.
  - References: Coder docs on templates and long-lived tokens; Flux Kustomization `force`/`ssa` docs.

- [ ] **Step 3: Validate + commit**

```bash
git add cluster/apps/coder-system/coder-template-sync/README.md
git commit -m "docs(coder): README for coder-template-sync

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
kubectl -n coder-system get jobs -l app.kubernetes.io/name=coder-template-push
kubectl -n coder-system logs job/coder-template-push
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
- **Adding a new template:** create directory under `cluster/apps/coder-system/coder-template-sync/app/templates/<name>/`, add its files to the `configMapGenerator.files` list in `app/kustomization.yaml`, commit, push. Job runs automatically on merge.
