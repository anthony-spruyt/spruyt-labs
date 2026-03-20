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

Without this, the Talos SA controller cannot provision the secret, and the deployment will fail to mount credentials. Flux will retry with backoff, but the HelmRelease will remain in a failed state until the Talos config is applied.

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

- **Pod-level securityContext:** Change to `runAsUser: 10001, runAsGroup: 10001`. Do NOT set `runAsNonRoot: true` at pod level — the init container requires root and Kubernetes rejects `runAsUser: 0` when `runAsNonRoot: true` is set at pod level.
- **Init container securityContext:** Add explicit `runAsUser: 0, runAsGroup: 0` override (required for `apt-get`). Also set `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, and `readOnlyRootFilesystem: false` (explicit, since `apt-get` writes to root filesystem).
- **Main container securityContext:** Set `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `seccompProfile: type: RuntimeDefault`. Note: emptyDir mounts (`/tools`) remain writable — `readOnlyRootFilesystem` only affects the container's root filesystem, not volume mounts.
- **Seccomp profile:** Set `seccompProfile: type: RuntimeDefault` at pod level so it applies to both init and main containers.
- **Remove `reloader.stakater.com/auto` annotation:** The Talos SA controller auto-rotates the credential secret. With the reloader annotation, every rotation would restart the orchestrator — resetting the `on_battery_since` counter and potentially delaying an in-progress shutdown. The orchestrator does not need to restart on secret rotation; talosctl reads credentials from disk on each invocation.

#### Image pinning

Do NOT pin image digests. The Renovate config (`.github/renovate.json5`) explicitly sets `pinDigests: false` for docker/OCI images. Adding digests manually would conflict with Renovate's management of these images. The `bitnami/kubectl:latest` tag is used consistently across the repo and is the only published tag for this image.

#### Persistence note

The app-template `persistence` block with `type: secret` generates a standard Kubernetes `volumes[].secret.secretName` + `volumeMounts[].mountPath` spec. Verify the rendered output produces:
- `volumes[].secret.secretName: shutdown-orchestrator-talos-secrets`
- `volumeMounts[].mountPath: /var/run/secrets/talos.dev`
- `volumeMounts[].readOnly: true`

#### automountServiceAccountToken

The Kubernetes ServiceAccount (`shutdown-orchestrator` in `rbac.yaml`) does not set `automountServiceAccountToken: false`. This is intentional — the orchestrator needs the SA token for kubectl operations (CNPG hibernation, Ceph operations, node management). The etcd-defrag pattern sets it to `false` because it only uses talosctl, not kubectl.

### 4. Kustomization Update

**File:** `cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml`

- Remove `talosconfig-secret.sops.yaml` from resources (note: this file was already deleted from the working tree but the reference remains — currently a broken reference)
- Add `talos-serviceaccount.yaml` to resources

### 5. Recovery Job

**File:** `cluster/apps/nut-system/shutdown-orchestrator/app/recovery-job.yaml`

No changes. The recovery job already has `seccompProfile: RuntimeDefault` and `readOnlyRootFilesystem: true`. Image digest pinning is not used per Renovate config. Note: this file is not included in the kustomization (applied manually after power restoration).

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

## No Changes Required

- **shutdown-script-configmap.yaml** — `talosctl` auto-discovers credentials at `/var/run/secrets/talos.dev`, no script changes needed
- **recovery-script-configmap.yaml** — recovery script uses `kubectl` only, not `talosctl`
- **recovery-job.yaml** — already has seccomp + read-only root filesystem; no digest pinning per Renovate config
- **rbac.yaml** — Kubernetes RBAC unchanged (SA name stays `shutdown-orchestrator`); `automountServiceAccountToken` intentionally not set to `false` (kubectl needs the token)
- **vpa.yaml** — resource limits unchanged; init container has no resource specs so no VPA policy needed per patterns doc
- **ks.yaml** — no dependency changes

## Risks

| Risk | Mitigation |
|------|------------|
| Talos configs not applied before deploy | Elevated to prerequisite section; Flux HelmRelease will fail until secret is provisioned (obvious, self-healing once Talos config is applied) |
| `os:operator` broader than needed | Minimum role for shutdown; no finer-grained option exists in Talos RBAC |
| `nut-system` namespace expansion | Low risk — only workloads with RBAC to create Talos SA CRDs can obtain credentials |
| Init container runs as root | Required for `apt-get install nut-client`; explicit container-level override with minimal capabilities; main container is fully hardened; init is ephemeral. Namespace PSA is `privileged` so no admission rejection. |
| SA secret rotation during power event | Reloader annotation removed; talosctl reads creds from disk per-invocation; no restart on rotation |
| `runAsNonRoot` not set at pod level | Cannot set at pod level due to root init container conflict; set on main container only. Future improvement: eliminate root init requirement by pre-building a container image with tools baked in. |
