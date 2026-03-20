# Shutdown Orchestrator: Talos ServiceAccount CRD Migration

**Issue:** #578
**Date:** 2026-03-20

## Summary

Migrate shutdown-orchestrator from static `TALOSCONFIG` env var + SOPS-encrypted talosconfig secret to Talos `ServiceAccount` CRD (`talos.dev/v1alpha1`) for talosctl authentication. Includes security hardening of the deployment.

## Motivation

The etcd-defrag CronJob already uses the recommended Talos SA CRD pattern. The shutdown-orchestrator still uses the legacy approach with a manually managed talosconfig secret. The SA CRD approach provides:

- **Scoped credentials** — explicitly `os:operator` vs potentially admin-level static config
- **Auto-rotation** — credentials managed by Talos SA controller, not manually
- **No secrets in git** — eliminates SOPS-encrypted talosconfig from the repo
- **Consistency** — standardizes on a single auth pattern across talosctl workloads

## Prerequisites

**Before deploying the cluster/ changes**, Talos machine configs must be updated to allow SA CRDs in `nut-system`:

1. Edit `talos/patches/control-plane/enable-talos-api-access.yaml` (step 1 below)
2. Regenerate configs: `talhelper genconfig`
3. Apply to all control plane nodes: `talosctl apply-config`
4. Verify: confirm Talos API access is updated on all control plane nodes

Without this, the Talos SA controller cannot provision the secret, and the deployment will fail to mount credentials.

## Design

### 1. Talos API Access Patch

**File:** `talos/patches/control-plane/enable-talos-api-access.yaml`

Add `nut-system` to `allowedKubernetesNamespaces`:

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

### 2. Talos ServiceAccount CRD

**New file:** `cluster/apps/nut-system/shutdown-orchestrator/app/talos-serviceaccount.yaml`

Following the etcd-defrag pattern:

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

The Talos SA controller creates a Secret named `shutdown-orchestrator-talos-secrets` containing the credentials.

### 3. Values Changes

**File:** `cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml`

#### Auth migration

- Remove `TALOSCONFIG` env var (talosctl auto-discovers at `/var/run/secrets/talos.dev`)
- Replace `talos` persistence (secret `talosconfig-secret` at `/talos`) with `talos-secrets` persistence (secret `shutdown-orchestrator-talos-secrets` at `/var/run/secrets/talos.dev`, readOnly)

#### Security hardening

- **Pod-level securityContext:** Change to `runAsUser: 10001, runAsGroup: 10001` (non-root default for all containers)
- **Init container override:** Add explicit `securityContext.runAsUser: 0, runAsGroup: 0` on the `install-tools` init container, since it needs root for `apt-get`. Without this override, the init container would inherit the pod-level non-root UID and fail.
- **Main container read-only root filesystem:** Set `readOnlyRootFilesystem: true`. Note: emptyDir mounts (`/tools`) remain writable — `readOnlyRootFilesystem` only affects the container's root filesystem, not volume mounts.
- **Seccomp profile:** Add `seccompProfile: type: RuntimeDefault` to main container
- **Pin image digest:** Use `bitnami/kubectl:latest@sha256:7fc66a99e38500a5ceb81583856f89ee589bdffd885c895e42a76dce45a3bc73` for both init and main containers (Renovate auto-updates digests)
- **Remove `reloader.stakater.com/auto` annotation:** The Talos SA controller auto-rotates the credential secret. With the reloader annotation, every rotation would restart the orchestrator — resetting the `on_battery_since` counter and potentially delaying an in-progress shutdown. The orchestrator does not need to restart on secret rotation; talosctl reads credentials from disk on each invocation.

#### Persistence note

The app-template `persistence` block with `type: secret` generates a standard Kubernetes `volumes[].secret.secretName` + `volumeMounts[].mountPath` spec. Verify the rendered output produces:
- `volumes[].secret.secretName: shutdown-orchestrator-talos-secrets`
- `volumeMounts[].mountPath: /var/run/secrets/talos.dev`
- `volumeMounts[].readOnly: true`

### 4. Kustomization Update

**File:** `cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml`

- Remove `talosconfig-secret.sops.yaml` from resources (note: this file was already deleted from the working tree but the reference remains — currently a broken reference)
- Add `talos-serviceaccount.yaml` to resources

### 5. Recovery Job Hardening

**File:** `cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml`

- Pin `bitnami/kubectl` image by digest
- Note: `seccompProfile: RuntimeDefault` and `readOnlyRootFilesystem: true` are already present in the current file — no changes needed for those

### 6. Delete Legacy Secret

**Delete:** `cluster/apps/nut-system/shutdown-orchestrator/app/talosconfig-secret.sops.yaml`

Already absent from working tree. No action needed — the kustomization reference removal (step 4) is the actual fix.

## Files Changed

| File | Action |
|------|--------|
| `talos/patches/control-plane/enable-talos-api-access.yaml` | Edit — add `nut-system` |
| `cluster/apps/nut-system/shutdown-orchestrator/app/talos-serviceaccount.yaml` | Create |
| `cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml` | Edit — auth + security |
| `cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml` | Edit — swap resources |
| `cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml` | Edit — pin image digest |

## No Changes Required

- **shutdown-script-configmap.yaml** — `talosctl` auto-discovers credentials at `/var/run/secrets/talos.dev`, no script changes needed
- **recovery-script-configmap.yaml** — recovery script uses `kubectl` only, not `talosctl`
- **rbac.yaml** — Kubernetes RBAC unchanged (SA name stays `shutdown-orchestrator`)
- **vpa.yaml** — resource limits unchanged
- **ks.yaml** — no dependency changes

## Risks

| Risk | Mitigation |
|------|------------|
| Talos configs not applied before deploy | Elevated to prerequisite section; deployment will fail obviously (secret not provisioned) |
| `os:operator` broader than needed | Minimum role for shutdown; no finer-grained option exists in Talos RBAC |
| `nut-system` namespace expansion | Low risk — only workloads with RBAC to create Talos SA CRDs can obtain credentials |
| Init container still runs as root | Required for `apt-get`; explicit container-level override; main container is hardened; init is ephemeral |
| SA secret rotation during power event | Reloader annotation removed; talosctl reads creds from disk per-invocation; no restart on rotation |
