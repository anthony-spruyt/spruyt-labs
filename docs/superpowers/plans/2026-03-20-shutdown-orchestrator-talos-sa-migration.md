# Shutdown Orchestrator Talos SA Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate shutdown-orchestrator from static talosconfig secret to Talos ServiceAccount CRD auth, with security hardening.

**Architecture:** Replace SOPS-encrypted talosconfig with a `talos.dev/v1alpha1` ServiceAccount CRD that auto-provisions credentials at `/var/run/secrets/talos.dev`. Harden pod security (non-root main container, seccomp, read-only rootfs, digest pinning). Remove reloader annotation to prevent restarts on credential rotation.

**Tech Stack:** Talos Linux, FluxCD, bjw-s app-template Helm chart, Kustomize

**Spec:** `docs/superpowers/specs/2026-03-20-shutdown-orchestrator-talos-sa-migration-design.md`
**Issue:** #578

---

### Task 0: Create Feature Branch

- [ ] **Step 1: Create feature branch from latest main**

```bash
git checkout -b chore/shutdown-orchestrator-talos-sa-migration origin/main
```

All subsequent commits land on this branch.

---

### Task 1: Talos API Access Patch

**Files:**
- Modify: `talos/patches/control-plane/enable-talos-api-access.yaml`

- [ ] **Step 1: Add `nut-system` to allowedKubernetesNamespaces**

```yaml
machine:
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles:
        - os:operator
      allowedKubernetesNamespaces:
        - kube-system
        - nut-system
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint talos/patches/control-plane/enable-talos-api-access.yaml`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add talos/patches/control-plane/enable-talos-api-access.yaml
git commit -m "chore(nut-system): allow Talos SA CRDs in nut-system namespace

Add nut-system to allowedKubernetesNamespaces so the Talos SA controller
can provision credentials for the shutdown-orchestrator.

NOTE: Requires talhelper genconfig + talosctl apply-config before cluster
changes are deployed.

Ref #578"
```

---

### Task 2: Create Talos ServiceAccount CRD

**Files:**
- Create: `cluster/apps/nut-system/shutdown-orchestrator/app/talos-serviceaccount.yaml`

**Reference:** `cluster/apps/kube-system/etcd-defrag/app/serviceaccount.yaml`

- [ ] **Step 1: Create the Talos ServiceAccount CRD file**

```yaml
---
apiVersion: talos.dev/v1alpha1
kind: ServiceAccount
metadata:
  name: shutdown-orchestrator-talos-secrets
  namespace: nut-system
spec:
  roles:
    - os:operator
```

- [ ] **Step 2: Validate YAML syntax**

Run: `yamllint cluster/apps/nut-system/shutdown-orchestrator/app/talos-serviceaccount.yaml`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add cluster/apps/nut-system/shutdown-orchestrator/app/talos-serviceaccount.yaml
git commit -m "chore(nut-system): add Talos ServiceAccount CRD for shutdown-orchestrator

Provisions os:operator credentials auto-mounted at /var/run/secrets/talos.dev.
Replaces the legacy SOPS-encrypted talosconfig secret.

Ref #578"
```

---

### Task 3: Update Kustomization

**Files:**
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml`
- Delete: `cluster/apps/nut-system/shutdown-orchestrator/app/talosconfig-secret.sops.yaml`

- [ ] **Step 1: Replace talosconfig-secret.sops.yaml with talos-serviceaccount.yaml**

In the `resources:` list, replace `./talosconfig-secret.sops.yaml` with `./talos-serviceaccount.yaml`.

Before:

```yaml
resources:
  - ./rbac.yaml
  - ./shutdown-script-configmap.yaml
  - ./recovery-script-configmap.yaml
  - ./talosconfig-secret.sops.yaml
  - ./release.yaml
  - ./vpa.yaml
  # NOTE: recovery-job.yaml is NOT included - apply manually after power restoration:
  #   kubectl apply -f cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml
```

After:

```yaml
resources:
  - ./rbac.yaml
  - ./shutdown-script-configmap.yaml
  - ./recovery-script-configmap.yaml
  - ./talos-serviceaccount.yaml
  - ./release.yaml
  - ./vpa.yaml
  # NOTE: recovery-job.yaml is NOT included - apply manually after power restoration:
  #   kubectl apply -f cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml
```

- [ ] **Step 2: Validate kustomize build**

Run: `kubectl kustomize cluster/apps/nut-system/shutdown-orchestrator/app/`
Expected: Renders without errors. Output should include the `talos.dev/v1alpha1 ServiceAccount` resource.

- [ ] **Step 3: Delete the legacy SOPS secret file**

```bash
git rm cluster/apps/nut-system/shutdown-orchestrator/app/talosconfig-secret.sops.yaml
```

This removes the SOPS-encrypted talosconfig from the repo. The Talos SA CRD replaces it.

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml
git commit -m "chore(nut-system): swap talosconfig secret for Talos SA CRD in kustomization

Remove talosconfig-secret.sops.yaml (replaced by Talos SA CRD) and update
kustomization to reference talos-serviceaccount.yaml.

Ref #578"
```

Note: `git rm` in step 3 already stages the deletion, so the commit includes both changes.

---

### Task 4: Update Values — Auth Migration

**Files:**
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml`

This task handles the core auth migration. Security hardening is in Task 5.

- [ ] **Step 1: Remove the TALOSCONFIG env var**

Remove these two lines from `controllers.orchestrator.containers.app.env`:

```yaml
          - name: TALOSCONFIG
            value: /talos/talosconfig
```

talosctl auto-discovers credentials at `/var/run/secrets/talos.dev`.

- [ ] **Step 2: Replace talos persistence with talos-secrets**

Replace the `talos` persistence block:

Before:

```yaml
  talos:
    type: secret
    name: talosconfig-secret
    globalMounts:
      - path: /talos
        readOnly: true
```

After:

```yaml
  talos-secrets:
    type: secret
    name: shutdown-orchestrator-talos-secrets
    globalMounts:
      - path: /var/run/secrets/talos.dev
        readOnly: true
```

- [ ] **Step 3: Remove reloader annotation**

Remove the `annotations` block from `controllers.orchestrator`:

```yaml
    annotations:
      reloader.stakater.com/auto: "true"
```

The Talos SA controller rotates credentials automatically. talosctl reads from disk on each invocation — no pod restart needed. Removing this prevents restarts during credential rotation that could interrupt an in-progress shutdown sequence.

- [ ] **Step 4: Validate kustomize build**

Run: `kubectl kustomize cluster/apps/nut-system/shutdown-orchestrator/app/`
Expected: Renders without errors. Verify the rendered output contains:
- No `TALOSCONFIG` env var
- A volume with `secretName: shutdown-orchestrator-talos-secrets`
- A volumeMount at `/var/run/secrets/talos.dev` with `readOnly: true`
- No `reloader.stakater.com/auto` annotation

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml
git commit -m "chore(nut-system): migrate shutdown-orchestrator to Talos SA CRD auth

- Remove TALOSCONFIG env var (talosctl auto-discovers at /var/run/secrets/talos.dev)
- Replace talosconfig-secret mount with Talos SA CRD secret mount
- Remove reloader annotation to prevent restarts on credential rotation

Ref #578"
```

---

### Task 5: Update Values — Security Hardening

**Files:**
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml`

- [ ] **Step 1: Harden pod-level securityContext**

Replace the pod `securityContext` block:

Before:

```yaml
      securityContext:
        runAsUser: 0
        runAsGroup: 0
```

After:

```yaml
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
```

Do NOT add `runAsNonRoot: true` here — the init container needs root.

- [ ] **Step 2: Add init container securityContext**

Add a `securityContext` block to `controllers.orchestrator.initContainers.install-tools`, at the same level as `image:` and `command:`:

```yaml
    initContainers:
      install-tools:
        image:
          ...
        securityContext:          # <-- insert here
          runAsUser: 0
          runAsGroup: 0
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          capabilities:
            drop:
              - ALL
        command:
          ...
```

This overrides the pod-level non-root UID. `readOnlyRootFilesystem: false` is explicit because `apt-get` writes to the root filesystem.

- [ ] **Step 3: Harden main container securityContext**

Replace the main container `securityContext`:

Before:

```yaml
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          capabilities:
            drop:
              - ALL
```

After:

```yaml
        securityContext:
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
          seccompProfile:
            type: RuntimeDefault
```

`readOnlyRootFilesystem: true` is safe because the main container only writes to emptyDir mounts (`/tools`, `/tmp`), which are unaffected.

- [ ] **Step 4: Add `/tmp` emptyDir persistence**

Add a `tmp` emptyDir to the `persistence:` block in values.yaml. `talosctl` and `kubectl` may write temporary files to `/tmp` (TLS session caching, credential files). Without this, those writes fail with EROFS when `readOnlyRootFilesystem: true`. This follows the etcd-defrag reference pattern (`cronjob.yaml` lines 123-130).

Add after the existing `tools` persistence entry:

```yaml
  tmp:
    type: emptyDir
    globalMounts:
      - path: /tmp
```

- [ ] **Step 5: Pin image digests**

Update both image tags from `latest` to `latest@sha256:7fc66a99e38500a5ceb81583856f89ee589bdffd885c895e42a76dce45a3bc73`.

Init container:

```yaml
          tag: latest@sha256:7fc66a99e38500a5ceb81583856f89ee589bdffd885c895e42a76dce45a3bc73
```

Main container:

```yaml
          tag: latest@sha256:7fc66a99e38500a5ceb81583856f89ee589bdffd885c895e42a76dce45a3bc73
```

This follows the existing repo pattern (see `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/values.yaml`). Renovate will auto-update the digest on future changes.

- [ ] **Step 6: Validate kustomize build**

Run: `kubectl kustomize cluster/apps/nut-system/shutdown-orchestrator/app/`
Expected: Renders without errors. Verify:
- Pod securityContext has `runAsUser: 10001`, `seccompProfile: RuntimeDefault`
- Init container has `runAsUser: 0`, `allowPrivilegeEscalation: false`
- Main container has `runAsNonRoot: true`, `readOnlyRootFilesystem: true`
- Both images include the `@sha256:` digest
- A `/tmp` emptyDir volume and mount exists

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml
git commit -m "chore(nut-system): harden shutdown-orchestrator security

- Pod runs as non-root (10001:10001) with seccomp RuntimeDefault
- Init container explicit root override for apt-get
- Main container: runAsNonRoot, readOnlyRootFilesystem, seccomp
- Add /tmp emptyDir for talosctl/kubectl temp file writes
- Pin bitnami/kubectl image by digest

Ref #578"
```

---

### Task 6: Pin Recovery Job Image Digest

**Files:**
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml`

- [ ] **Step 1: Pin the image digest**

Replace:

```yaml
          image: bitnami/kubectl:latest
```

With:

```yaml
          image: bitnami/kubectl:latest@sha256:7fc66a99e38500a5ceb81583856f89ee589bdffd885c895e42a76dce45a3bc73
```

Note: This file is not in the kustomization (applied manually), so Renovate may not auto-discover it for digest updates. This is acceptable — the recovery job is rarely used and the image will still work even if the digest drifts.

- [ ] **Step 2: Commit**

```bash
git add cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml
git commit -m "chore(nut-system): pin recovery job image digest

Ref #578"
```

---

### Task 7: Run qa-validator

- [ ] **Step 1: Run qa-validator**

Dispatch the `qa-validator` subagent (Agent tool with `subagent_type: "qa-validator"`). It runs MegaLinter, schema validation, and kustomize dry-runs against all modified files.

Expected: All checks pass (yamllint, kustomize build, schema validation).

- [ ] **Step 2: Fix any issues found and re-run if needed**

---

### Task 8: Create Pull Request

- [ ] **Step 1: Push and create PR**

```bash
gh pr create --title "chore(nut-system): migrate shutdown-orchestrator to Talos SA CRD auth" --body "$(cat <<'PREOF'
## Summary
- Migrate shutdown-orchestrator talosctl auth from static talosconfig secret to Talos ServiceAccount CRD
- Harden security: non-root main container, seccomp, read-only rootfs, digest pinning
- Remove reloader annotation to prevent restarts on credential rotation

## Linked Issue
Closes #578

## Changes
- Add `nut-system` to Talos API access `allowedKubernetesNamespaces`
- Create `talos.dev/v1alpha1` ServiceAccount CRD with `os:operator` role
- Replace `TALOSCONFIG` env var + secret mount with auto-discovered SA credentials
- Harden pod/container security contexts
- Pin `bitnami/kubectl` images by digest
- Delete legacy SOPS-encrypted talosconfig secret
- Add /tmp emptyDir mount for readOnlyRootFilesystem compatibility

## Post-Merge Prerequisites
**Before Flux deploys these changes**, Talos machine configs must be updated:
1. `talhelper genconfig`
2. `talosctl apply-config` on all control plane nodes
3. Verify Talos API access updated

Without this, the Talos SA controller cannot provision the secret and the deployment will fail.

## Testing
- `kubectl kustomize` renders correctly
- qa-validator passes
- After Talos config applied + Flux reconcile: verify pod starts, credentials mounted at `/var/run/secrets/talos.dev`
PREOF
)"
```

- [ ] **Step 2: Verify PR created successfully**

Run: `gh pr view --web` to confirm.
