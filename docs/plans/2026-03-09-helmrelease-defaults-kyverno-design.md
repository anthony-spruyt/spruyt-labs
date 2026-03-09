# HelmRelease Defaults Kyverno Policy

## Problem

HelmRelease defaults (timeout, interval, install/upgrade/rollback strategies) are currently applied via Flux Kustomization patches in `cluster/flux/cluster/ks.yaml`. These patches use strategic merge, which **always overwrites** scalar fields — making it impossible for individual HelmReleases to override specific fields like `timeout` without opting out of all defaults via a label.

## Solution

Hybrid approach: add `interval` (a required CRD field) explicitly to every HelmRelease manifest, and use a Kyverno ClusterPolicy with `+(anchor)` syntax for optional fields.

## Lesson Learned (Attempt 1)

The initial approach put all fields including `interval` in the Kyverno policy. This failed because `spec.interval` is a **required field** in the HelmRelease CRD — Kubernetes server-side validation rejects manifests missing it *before* Kyverno's admission webhook can inject the default. Kyverno can only default optional fields.

## Design

### Explicit `interval` in all HelmRelease manifests

Add `interval: 4h` to the spec of all 45 HelmRelease `release.yaml` files. This is a required CRD field and must be present in the manifest before API server validation.

### New file: `cluster/apps/kyverno/policies/app/helmrelease-defaults.yaml`

ClusterPolicy with `patchStrategicMerge` using `+(field)` anchors for optional fields only:

- `+(timeout): 10m` — default timeout
- `+(install)` — CRD handling + RetryOnFailure strategy
- `+(rollback)` — cleanupOnFail + recreate
- `+(upgrade)` — CRD handling + RemediateOnFailure + remediation retries

Matches all HelmReleases on CREATE/UPDATE. No namespace exclusions needed.

### Changes to `cluster/flux/cluster/ks.yaml`

Remove the nested HelmRelease patch block including:
- The strategic merge patch for interval/install/rollback/upgrade
- The JSON patch for timeout
- The `helmreleasedefaults.flux.home.arpa/disabled` labelSelector

### Granularity

- **Individual fields:** `timeout` — per-field override via Kyverno
- **Explicit field:** `interval` — set directly in manifest, change per-release as needed
- **Top-level blocks:** `install`, `upgrade`, `rollback` — override as a unit via Kyverno

### Existing overrides preserved

- `openclaw/release.yaml` — `timeout: 15m` (Kyverno skips)
- `n8n/release.yaml` — `timeout: 15m` (Kyverno skips)
- `rook-ceph-cluster/release.yaml` — `timeout: 15m` (Kyverno skips)
- `cilium/release.yaml` — `timeout: 2m` (Kyverno skips)

## Trade-offs

- **Pro:** True "default if not set" semantics for optional fields
- **Pro:** `interval` visible in each manifest — explicit, greppable
- **Pro:** Follows established Kyverno pattern (PSS policy uses same `+(anchor)` syntax)
- **Pro:** Removes complex nested Flux patch indirection
- **Con:** 45 files touched to add `interval` (mechanical, low risk)
- **Con:** Kyverno dependency for HelmRelease defaults (already running)
