# Phase 1 — Unprivileged Coder Workspaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drop `privileged: true` from Coder workspaces by replacing envbuilder's dockerd with rootless Podman, lock `coder-system` namespace to PSA `restricted`, and close issue #910 via a dedicated `ssh-key-rotation` image.

**Architecture:** Inline Podman install in `.devcontainer/setup-devcontainer.sh`
(consumed by both local VS Code and envbuilder). Coder workspace pod spec
rewritten to non-root + dropped caps. `ssh-key-rotation` CronJob switches from
runtime `apk add` to a pre-built image (from `anthony-spruyt/container-images`)
with shell script extracted out of the manifest. Namespace PSA rolled out
staged: warn/audit → observe → enforce.

**Tech Stack:** Talos Linux, FluxCD, Kubernetes 1.35, Terraform (Coder templates), Kustomize, Podman rootless, Alpine-based custom images, SOPS.

**Tracking:** Umbrella #921 · This phase #932 · Next phase #933 · Closes #910

**Spec:** `docs/superpowers/specs/2026-04-15-coder-unprivileged-workspaces-design.md`

---

## Prerequisite — PR A in `anthony-spruyt/container-images`

This plan assumes PR A has merged and published `ghcr.io/anthony-spruyt/container-images/ssh-key-rotation:<TAG>` before Task 3 runs. PR A is executed in the `container-images` repo, not here; a minimal spec sketch follows so coordination is unambiguous.

**Image contract (what the CronJob expects):**

- Base: `alpine:3.23@sha256:<digest>` (match `chrony/Dockerfile` pin style)
- Build-time packages (no runtime `apk add`): `openssh-keygen`, `curl`, `jq`, `kubectl`, `ca-certificates`, `tzdata`
- Non-root user `rotator` with UID/GID `1000`
- `WORKDIR /home/rotator`
- Entrypoint script `/usr/local/bin/rotate-ssh-key.sh` containing the full rotation logic currently inlined in `cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml` lines 37–131. Port the script verbatim into the image; replace the shell-inlined `$${VAR}` Kustomize-escapes with plain `${VAR}` since it is no longer YAML-escaped.
- Script requirements (must not break under restricted PSA):
  - No `apk add`, `sudo`, or any write outside `/tmp`
  - Write keypair to `/tmp` (backed by `emptyDir` memory volume — `readOnlyRootFilesystem: true` allowed)
  - Read `GITHUB_PAT` from env
  - Use `kubectl` already baked into the image

**Verification (in PR A, before merging spruyt-labs Task 3):**

- Image builds successfully in the container-images repo CI
- Image is published to `ghcr.io/anthony-spruyt/container-images/ssh-key-rotation:<TAG>`
- Trivy scan passes at the repo's standard threshold
- The digest SHA is recorded — Task 3 will use `image: ghcr.io/anthony-spruyt/container-images/ssh-key-rotation:<TAG>@sha256:<digest>`

---

## File Manifest

**Created:**

- None in this repo (image lives in `container-images`).

**Modified:**

- `.devcontainer/devcontainer.json` — remove `docker-in-docker` feature
- `.devcontainer/setup-devcontainer.sh` — add Podman install block
- `.devcontainer/post-create.sh` — leave `docker run hello-world` check in place, add explicit "docker is podman" assertion
- `cluster/apps/coder-system/namespace.yaml` — staged PSA labels
- `cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml` — switch to custom image, remove inline script, tighten securityContext
- `coder/templates/devcontainer/main.tf` — security context rewrite

No test files per se — validation is live-cluster verification via `qa-validator` (pre-commit), `cluster-validator` (post-push), and targeted `kubectl`/`task` commands noted per task.

---

## Task 1 — Swap DinD feature for rootless Podman in devcontainer

**Goal:** `.devcontainer/devcontainer.json` no longer depends on `docker-in-docker`; `setup-devcontainer.sh` installs rootless Podman; `docker` CLI resolves to Podman in both local VS Code and Coder envbuilder builds.

**Files:**

- Modify: `.devcontainer/devcontainer.json`
- Modify: `.devcontainer/setup-devcontainer.sh`
- Modify: `.devcontainer/post-create.sh`

- [ ] **Step 1.1: Read the current devcontainer files to confirm line locations.**

Use Read tool:
- `.devcontainer/devcontainer.json`
- `.devcontainer/setup-devcontainer.sh`
- `.devcontainer/post-create.sh`

Confirm the `docker-in-docker` feature line in `devcontainer.json` and locate the end of `setup-devcontainer.sh` for the append target.

- [ ] **Step 1.2: Remove the `docker-in-docker` feature from `devcontainer.json`.**

Use Edit tool:

Old string:
```json
    "ghcr.io/devcontainers/features/docker-in-docker": {},
```

New string: (empty — remove the line entirely, including the trailing comma cleanup if it breaks JSON; verify JSON remains valid)

Verify with:
```bash
python3 -c "import json5; json5.load(open('.devcontainer/devcontainer.json'))" 2>/dev/null || \
  python3 -c "import json; json.load(open('.devcontainer/devcontainer.json'))"
```

- [ ] **Step 1.3: Add Podman install block to `setup-devcontainer.sh`.**

Append before any final `echo` of the script (or at a logical position near the top of the install sequence, before the script uses `docker`). Exact content:

```bash
# --- Rootless Podman (replaces docker-in-docker) ---
# podman-docker provides /usr/bin/docker symlink → podman
# uidmap + slirp4netns enable rootless user namespaces and networking
# fuse-overlayfs is used when kernel overlayfs-on-userns is unavailable
echo "Installing rootless Podman..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  podman \
  podman-docker \
  fuse-overlayfs \
  uidmap \
  slirp4netns

# Confirm the vscode user has subuid/subgid allocations (required for rootless)
if ! grep -q '^vscode:' /etc/subuid; then
  echo "vscode:100000:65536" | sudo tee -a /etc/subuid >/dev/null
fi
if ! grep -q '^vscode:' /etc/subgid; then
  echo "vscode:100000:65536" | sudo tee -a /etc/subgid >/dev/null
fi

# Suppress the podman-docker "emulated" MOTD on every docker invocation
sudo touch /etc/containers/nodocker
```

- [ ] **Step 1.4: Add an explicit assertion in `post-create.sh` that `docker` resolves to Podman.**

After the existing `docker run --rm hello-world` check block (around line 59–63), add:

```bash
# 1b. Confirm docker CLI is Podman (not a leftover dockerd)
if docker --version 2>&1 | grep -qi 'podman'; then
  pass "docker CLI resolves to Podman"
else
  fail "docker CLI is not Podman (got: $(docker --version 2>&1))"
fi
```

- [ ] **Step 1.5: Rebuild the devcontainer locally and run the verification script.**

In VS Code: `Dev Containers: Rebuild Container`. After the container is up:

```bash
bash .devcontainer/post-create.sh
```

Expected: all checks pass, including the new "docker CLI resolves to Podman" assertion.

Additional manual checks:
```bash
docker --version          # expect: podman version X.Y.Z
docker run --rm hello-world  # expect: "Hello from Docker!" message
task dev-env:lint         # expect: MegaLinter runs to completion (may surface lint findings — those are fine)
```

- [ ] **Step 1.6: Commit via qa-validator.**

Per `.claude/rules/02-validation.md`, run the `qa-validator` subagent before committing. When it approves:

```bash
git add .devcontainer/devcontainer.json .devcontainer/setup-devcontainer.sh .devcontainer/post-create.sh
git commit -m "feat(devcontainer): replace DinD with rootless Podman

Install podman + podman-docker in setup-devcontainer.sh so the same
devcontainer.json works under a non-privileged Coder pod. docker CLI
is symlinked to podman.

Ref #921 #932"
```

---

## Task 2 — Rewrite `ssh-key-rotation` CronJob to use the custom image under PSA restricted

**Goal:** CronJob pulls the prebuilt `ssh-key-rotation` image (PR A), runs as non-root with `readOnlyRootFilesystem: true`, drops inline shell. Closes #910 on next successful scheduled run.

**Files:**

- Modify: `cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml`

**Depends on:** PR A merged in `container-images` with published image digest.

- [ ] **Step 2.1: Record the published image digest from PR A.**

Resolve `<TAG>` and `<DIGEST>` via the GitHub Packages API (no container runtime required — avoids circular dependency on Task 1):

```bash
# List recent versions and their tags (null-safe against untagged entries):
gh api '/users/anthony-spruyt/packages/container/container-images%2Fssh-key-rotation/versions' \
  --jq '.[0:5] | .[] | {name, tags: (.metadata.container.tags // [])}'

# For the chosen tag, read the manifest digest. `first()` guarantees a single
# result if multiple versions share a tag (shouldn't happen but defensive):
DIGEST=$(gh api '/users/anthony-spruyt/packages/container/container-images%2Fssh-key-rotation/versions' \
  --jq 'first(.[] | select((.metadata.container.tags // []) | index("<TAG>")) | .name)')
echo "$DIGEST"

# Verify it is a real sha256 digest (ghcr.io Packages API returns the manifest sha256 as .name for OCI images):
[[ "$DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] && echo "OK: $DIGEST" || { echo "ERROR: not a digest"; exit 1; }
```

Store the resulting `<TAG>` and `sha256:<DIGEST>` — used in Step 2.2.

- [ ] **Step 2.2: Replace `cronjob.yaml` with a restricted-PSA-compatible manifest.**

Note intentional changes vs the current manifest:
- `restartPolicy: OnFailure` → `Never` (preserve failed pods for log inspection; was silently losing logs per #910)
- `backoffLimit: 2` → `3` (tolerate one transient network blip on curl to api.github.com)
- Add `ttlSecondsAfterFinished: 86400` (retain completed/failed jobs for 24h)
- Drop inline shell script (now baked into image entrypoint `/usr/local/bin/rotate-ssh-key.sh`)
- `readOnlyRootFilesystem: false` → `true` (script only writes to `/tmp` emptyDir)
- `runAsNonRoot: false`, `runAsUser: 0` → `true`, `1000`

Use Write tool to replace the full file with:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/master-standalone-strict/cronjob-batch-v1.json
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ssh-key-rotation
  namespace: coder-system
spec:
  schedule: "0 3 * * 1"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 3
      ttlSecondsAfterFinished: 86400
      template:
        metadata:
          labels:
            app: ssh-key-rotation
        spec:
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            fsGroup: 1000
            seccompProfile:
              type: RuntimeDefault
          serviceAccountName: ssh-key-rotation
          restartPolicy: Never
          containers:
            - name: rotate-ssh-key
              # Tag + digest pin, matching the existing pattern in this repo
              # (see current alpine/k8s image ref replaced by this change, and
              # chrony/Dockerfile's alpine:3.23@sha256:...). Tag for human
              # readability and Renovate tag resolution; digest for immutable
              # pin — Renovate's `pinDigests` reconciles both.
              image: ghcr.io/anthony-spruyt/container-images/ssh-key-rotation:<TAG>@sha256:<DIGEST>
              command: ["/usr/local/bin/rotate-ssh-key.sh"]
              env:
                - name: GITHUB_PAT
                  valueFrom:
                    secretKeyRef:
                      name: coder-ssh-rotation-token
                      key: GITHUB_PAT
              resources:
                requests:
                  cpu: 10m
                  memory: 32Mi
                limits:
                  cpu: 100m
                  memory: 128Mi
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
                sizeLimit: 64Mi
```

Replace `<TAG>` and `<DIGEST>` with the values from Step 2.1.

- [ ] **Step 2.3: Validate the manifest locally.**

```bash
kubectl --dry-run=client apply -f cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml
kubectl kustomize cluster/apps/coder-system/coder/app >/dev/null
```

Both must succeed without errors.

- [ ] **Step 2.4: Verify RBAC still matches.**

Read `cluster/apps/coder-system/coder/app/ssh-key-rotation/role.yaml`. Confirm the Role still grants `patch` on `secrets` in `coder-system` (for `coder-ssh-signing-key`). No RBAC changes expected — image runs as UID 1000 but the ServiceAccount is unchanged.

- [ ] **Step 2.5: Run qa-validator.**

Dispatch the qa-validator subagent. Address any findings.

- [ ] **Step 2.6: Commit.**

```bash
git add cluster/apps/coder-system/coder/app/ssh-key-rotation/cronjob.yaml
git commit -m "fix(coder): ssh-key-rotation uses custom image under restricted PSA

Replace alpine/k8s + runtime apk add with prebuilt custom image from
anthony-spruyt/container-images. Runs as non-root with RORFS and
drop-all caps. Closes #910 once next weekly run succeeds.

Closes #910
Ref #921 #932"
```

---

## Task 3 — Rewrite Coder workspace template security context

**Goal:** `coder/templates/devcontainer/main.tf` produces workspace pods that satisfy PSA `restricted`: no `privileged`, non-root, dropped caps.

**Files:**

- Modify: `coder/templates/devcontainer/main.tf` (lines 398–435 area; confirm with Read)

- [ ] **Step 3.1: Read current security_context blocks.**

```bash
# Use Read tool, offset 395, limit 50
```

Confirm:
- Pod-level `security_context { run_as_user = 0 }` around line 400
- Container-level `security_context { privileged = true }` around lines 433–435

- [ ] **Step 3.2: Replace pod-level security_context.**

Use Edit tool.

Old string (exact, includes the now-stale comment block):
```hcl
    # Root required for Docker-in-Docker; remoteUser in devcontainer.json
    # switches the agent shell to vscode.
    security_context {
      run_as_user = 0
    }
```

New string:
```hcl
    # Non-root (UID 1000, vscode) under PSA restricted. The workspace
    # uses rootless Podman instead of dockerd, so no root is needed.
    security_context {
      run_as_user     = 1000
      run_as_group    = 1000
      fs_group        = 1000
      run_as_non_root = true
    }
```

- [ ] **Step 3.3: Replace container-level security_context.**

Old string:
```hcl
      security_context {
        privileged = true
      }
```

New string:
```hcl
      security_context {
        privileged                 = false
        allow_privilege_escalation = false
        read_only_root_filesystem  = false
        capabilities {
          drop = ["ALL"]
        }
      }
```

- [ ] **Step 3.4: Validate the Terraform changes.**

```bash
cd coder/templates/devcontainer
terraform fmt -check
terraform validate
cd -
```

Both must pass. `terraform fmt -check` will fail if formatting is off — run `terraform fmt` to fix.

- [ ] **Step 3.5: Run qa-validator.**

Dispatch qa-validator subagent. Fix any findings.

- [ ] **Step 3.6: Commit.**

```bash
git add coder/templates/devcontainer/main.tf
git commit -m "feat(coder): non-root workspace pods with dropped capabilities

Drop privileged: true, run as UID 1000, enforce non-root and drop
all capabilities. Paired with rootless Podman in the devcontainer
(Task 1) so MegaLinter and other docker-run workloads continue to
work.

Ref #921 #932"
```

---

## Task 4 — Namespace PSA labels: warn + audit

**Goal:** `coder-system` namespace emits PSA warn/audit events for restricted violations without blocking admission. Flux reconciles the change.

**Files:**

- Modify: `cluster/apps/coder-system/namespace.yaml`

- [ ] **Step 4.1: Read current namespace manifest.**

Current content:
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: coder-system
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    descheduler.kubernetes.io/exclude: "true"
```

- [ ] **Step 4.2: Change `warn` and `audit` to `restricted`, leave `enforce` as `privileged` for now.**

Use Edit tool.

Old string:
```yaml
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
```

New string:
```yaml
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 4.3: Validate.**

```bash
kubectl --dry-run=client apply -f cluster/apps/coder-system/namespace.yaml
```

Must succeed.

- [ ] **Step 4.4: Run qa-validator.**

- [ ] **Step 4.5: Commit.**

```bash
git add cluster/apps/coder-system/namespace.yaml
git commit -m "feat(coder-system): PSA warn+audit restricted

Enable PSA warn and audit at restricted level while keeping enforce
at privileged. Generates warnings for non-compliant workloads without
breaking admission, for an observation window before flipping enforce.

Ref #921 #932"
```

---

## Task 5 — Push, post-deploy validation, and observation window

**Goal:** All Task 1–4 commits reach `main`; Flux reconciles; cluster-validator confirms no regressions; observation window begins.

- [ ] **Step 5.1: Push to `main`.**

Per the user-memory preference, pushing to main is permitted without asking.

```bash
git push origin main
```

- [ ] **Step 5.2: Wait for Flux reconciliation.**

```bash
flux reconcile kustomization cluster-apps --with-source -n flux-system
flux get kustomizations -n flux-system | grep coder-system
```

Expect READY=True on the coder-system kustomization.

- [ ] **Step 5.3: Dispatch the cluster-validator subagent.**

Standard post-push validation per `.claude/rules/02-validation.md`. Fix any rollback-worthy regressions before proceeding.

- [ ] **Step 5.4: Push the Coder template to the Coder server.**

```bash
cd coder/templates/devcontainer
coder login  # if not already logged in
coder templates push devcontainer -y
cd -
```

- [ ] **Step 5.5: Create a fresh test workspace.**

Via the Coder UI or:
```bash
coder create --template=devcontainer psa-test
coder ssh psa-test
```

Inside the workspace, run:
```bash
docker --version                        # expect podman
docker run --rm hello-world             # expect success
bash .devcontainer/post-create.sh       # all checks pass
task dev-env:lint                       # completes (lint findings ok)
```

From outside — **do not** use `kubectl get pod -o yaml` (materialises `envFrom` secretRef values to stdout, forbidden per `.claude/rules/01-constraints.md`). Use `-o json | jq` on only the securityContext paths:

```bash
POD=$(kubectl -n coder-workspaces get pod -l com.coder.workspace.name=psa-test \
  -o jsonpath='{.items[0].metadata.name}')

kubectl -n coder-workspaces get pod "$POD" -o json | jq '{
  pod_runAsUser:     .spec.securityContext.runAsUser,
  pod_runAsNonRoot:  .spec.securityContext.runAsNonRoot,
  pod_fsGroup:       .spec.securityContext.fsGroup,
  containers: [.spec.containers[] | {
    name,
    privileged:                 .securityContext.privileged,
    allowPrivilegeEscalation:   .securityContext.allowPrivilegeEscalation,
    runAsNonRoot:               .securityContext.runAsNonRoot,
    runAsUser:                  .securityContext.runAsUser,
    capabilities_drop:          .securityContext.capabilities.drop
  }]
}'
```

Expected output shape:

```json
{
  "pod_runAsUser": 1000,
  "pod_runAsNonRoot": true,
  "pod_fsGroup": 1000,
  "containers": [
    {
      "name": "dev",
      "privileged": false,
      "allowPrivilegeEscalation": false,
      "runAsNonRoot": null,
      "runAsUser": null,
      "capabilities_drop": ["ALL"]
    }
  ]
}
```

(Container-level `runAsUser`/`runAsNonRoot` inherit from pod-level; `null` here is correct.) Any `privileged: true`, missing `["ALL"]` capability drop, or `allowPrivilegeEscalation: true` is a BLOCKER — fix before proceeding.

- [ ] **Step 5.6: Trigger ssh-key-rotation manually and verify.**

```bash
kubectl -n coder-system create job ssh-key-rotation-manual --from=cronjob/ssh-key-rotation
kubectl -n coder-system wait --for=condition=complete job/ssh-key-rotation-manual --timeout=5m
kubectl -n coder-system logs job/ssh-key-rotation-manual
```

Expect: completion, no PSA violations, both auth and signing keys registered on GitHub.

- [ ] **Step 5.7: Start the observation window.**

Record the start time. Required: **minimum 48 hours** between entering warn/audit (already live after Task 4 push) and flipping `enforce` in Task 6. Spec allows ≥ 24h; choosing 48h gives one weekly CronJob cycle (`ssh-key-rotation` runs Mondays 03:00 UTC) room to surface inside the window.

During the window, periodically:

```bash
kubectl -n coder-system get events --sort-by=.lastTimestamp \
  | grep -iE 'violat|polic|restrict' || echo "no violations"
```

- [ ] **Step 5.7a: Explicit pre-enforce PSA audit of every workload in `coder-system`.**

Because spec Unit 5 flags "Coder HelmRelease values may need an explicit securityContext override" as an open question, do not rely on event grep alone — actively probe each workload.

List every pod in the namespace and check its securityContext against restricted requirements. Use `-o json | jq` to avoid the multi-container ambiguity of `jsonpath`:

```bash
kubectl -n coder-system get pods -o json | jq -r '
  .items[] | {
    pod: .metadata.name,
    pod_runAsNonRoot: .spec.securityContext.runAsNonRoot,
    containers: [.spec.containers[] | {
      name,
      privileged: .securityContext.privileged,
      allowPrivilegeEscalation: .securityContext.allowPrivilegeEscalation,
      runAsNonRoot: .securityContext.runAsNonRoot,
      drop: .securityContext.capabilities.drop
    }]
  }'
```

For each pod, verify every container satisfies:
- `privileged: false` or `null`
- `allowPrivilegeEscalation: false`
- `runAsNonRoot: true` (at pod or container level)
- `capabilities.drop` contains `"ALL"`

Any pod failing these checks must be fixed BEFORE Task 6. Likely candidates:
- `coder` deployment (control plane) — adjust `securityContext` in `cluster/apps/coder-system/coder/app/values.yaml`
- `coder-cnpg-*` (CloudNativePG) — check upstream chart values
- `*-vpa` (VerticalPodAutoscaler objects produce no pods; the VPA operator itself lives in `kube-system`, out of scope)

For any workload requiring a values.yaml update, make the change, commit with `fix(coder-system): PSA restricted compliance for <workload>`, push, let Flux reconcile, re-run the probe. Only proceed to Task 6 when every pod in `coder-system` passes.

If a Helm chart does not expose securityContext values for a workload, escalate — flip enforce stays blocked until resolved (may require a chart fork or an admission policy exception).

- [ ] **Step 5.8: Destroy the test workspace.**

```bash
coder delete psa-test -y
```

- [ ] **Step 5.9: Confirm #910 ready to close.**

Wait for the next scheduled Monday 03:00 UTC run (or rely on the manual success from Step 5.6). Once the scheduled run completes clean once:

```bash
gh issue close 910 --repo anthony-spruyt/spruyt-labs \
  --comment "Resolved by ssh-key-rotation custom image + restricted PSA-compliant pod spec. See #932."
```

Skip this step if the scheduled run has not yet occurred — leave #910 open until it has.

---

## Task 6 — Flip namespace PSA `enforce` to restricted

**Goal:** `coder-system` namespace refuses any non-compliant pod. The cliff commit.

**Only do this task after the Task 5.7 observation window has elapsed with zero violations.**

**Files:**

- Modify: `cluster/apps/coder-system/namespace.yaml`

- [ ] **Step 6.1: Verify observation window is clean.**

```bash
# Last 72h of events:
kubectl -n coder-system get events --sort-by=.lastTimestamp \
  | grep -iE 'violat|polic|restrict' || echo "clean"
```

Must report `clean`. If any violations exist, stop — fix the offending workload first and restart the observation window.

- [ ] **Step 6.2: Change `enforce` label to `restricted`.**

Use Edit tool.

Old string:
```yaml
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

New string:
```yaml
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

- [ ] **Step 6.3: qa-validator.**

- [ ] **Step 6.4: Commit and push.**

```bash
git add cluster/apps/coder-system/namespace.yaml
git commit -m "feat(coder-system): PSA enforce restricted

Final cliff commit: coder-system refuses any non-compliant pod.
Workspace pods and ssh-key-rotation CronJob are restricted-compliant
(Tasks 2, 3). Rollback = revert this commit.

Ref #921 #932"
git push origin main
```

- [ ] **Step 6.5: Dispatch cluster-validator.**

Standard post-push validation. Watch specifically for `FailedCreate` events in `coder-system` — those indicate a workload the observation window missed.

- [ ] **Step 6.6: Smoke test.**

Create another test workspace to confirm admission still works:

```bash
coder create --template=devcontainer psa-smoke
coder delete psa-smoke -y
```

- [ ] **Step 6.7: Post-enforce 48h observation.**

Spec success-criteria requires "no `FailedCreate` events in `coder-system` for 48h after enforce". Do not close #932 until this window elapses cleanly.

Check at 24h and 48h:

```bash
kubectl -n coder-system get events --sort-by=.lastTimestamp \
  --field-selector reason=FailedCreate \
  -o jsonpath='{range .items[*]}{.lastTimestamp}{"\t"}{.message}{"\n"}{end}'
```

Expect empty. Also confirm:
- Coder control plane pods Ready
- CNPG postgres pods Ready
- Next scheduled `ssh-key-rotation` run (if it falls inside the window) succeeds

If any `FailedCreate` appears, roll back per the Rollback Playbook and restart the observation window after fixing.

- [ ] **Step 6.8: Tick Phase 1 checkbox in #921.**

```bash
gh issue view 921 --repo anthony-spruyt/spruyt-labs --json body --jq .body > /tmp/issue921.md
# manually tick `- [x] **Phase 1 — #932**: ...` in /tmp/issue921.md
gh issue edit 921 --repo anthony-spruyt/spruyt-labs --body-file /tmp/issue921.md
gh issue close 932 --repo anthony-spruyt/spruyt-labs \
  --comment "Implemented. Workspaces run unprivileged under rootless Podman; coder-system at PSA enforce=restricted."
```

---

## Rollback Playbook

| Failure | Revert strategy |
| --- | --- |
| Podman doesn't handle a workload | `git revert` Task 1 commit + Task 3 commit; `coder templates push`; existing workspaces recreated |
| ssh-key-rotation crashes on new image | `git revert` Task 2 commit; revert restores old image + inline script (still requires privileged, which is still allowed pre-Task 6) |
| PSA warn/audit floods events | `git revert` Task 4 commit |
| PSA enforce blocks a workload (Task 6) | `git revert` Task 6 commit; returns namespace to warn/audit-only |

Each revert is a single commit. Push and Flux reconciles.

---

## Self-Review

**Spec coverage:**

| Spec section | Covered by |
| --- | --- |
| Unit 1 — devcontainer | Task 1 |
| Unit 2 — Coder workspace template | Task 3 |
| Unit 3 — custom image | Prerequisite section (PR A) |
| Unit 4 — ssh-key-rotation CronJob | Task 2 |
| Unit 5 — namespace PSA staged rollout | Tasks 4 (warn/audit), 5 (observation), 6 (enforce) |
| Validation checks | Task 5 steps 5.5, 5.6; Task 6.6 |
| Rollback Playbook | End of plan |

**Placeholder scan:** `<TAG>` and `<DIGEST>` in Task 2 are substituted during Step 2.1–2.2 from PR A outputs. These are parameterised, not placeholder-as-gap.

**Type/name consistency:** Image name `ghcr.io/anthony-spruyt/container-images/ssh-key-rotation` consistent between prerequisite and Task 2. Security context field names match Kubernetes schema. UID 1000 consistent between image (prerequisite), CronJob (Task 2), and workspace template (Task 3).
