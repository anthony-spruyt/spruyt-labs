# HelmRelease Defaults Kyverno Policy

## Problem

HelmRelease defaults (timeout, interval, install/upgrade/rollback strategies) are currently applied via Flux Kustomization patches in `cluster/flux/cluster/ks.yaml`. These patches use strategic merge, which **always overwrites** scalar fields — making it impossible for individual HelmReleases to override specific fields like `timeout` without opting out of all defaults via a label.

## Solution

Move HelmRelease defaults from Flux patches to a Kyverno ClusterPolicy using `+(anchor)` syntax, which only sets fields that are not already present.

## Design

### New file: `cluster/apps/kyverno/policies/app/helmrelease-defaults.yaml`

ClusterPolicy with `patchStrategicMerge` using `+(field)` anchors:

- `+(timeout): 10m` — default timeout
- `+(interval): 4h` — default reconciliation interval
- `+(install)` — CRD handling + RetryOnFailure strategy
- `+(rollback)` — cleanupOnFail + recreate
- `+(upgrade)` — CRD handling + RemediateOnFailure + remediation retries

Matches all HelmReleases on CREATE/UPDATE. No namespace exclusions needed (HelmReleases only exist in app namespaces).

### Changes to `cluster/flux/cluster/ks.yaml`

Remove the nested HelmRelease patch block (lines 132-173) including:
- The strategic merge patch for interval/install/rollback/upgrade
- The JSON patch for timeout (unstaged)
- The `helmreleasedefaults.flux.home.arpa/disabled` labelSelector

### Granularity

- **Individual fields:** `timeout`, `interval` — per-field override
- **Top-level blocks:** `install`, `upgrade`, `rollback` — override as a unit

### Existing overrides preserved

- `openclaw/release.yaml` — `timeout: 15m` (kept)
- `n8n/release.yaml` — `timeout: 15m` (kept)
- `rook-ceph-cluster/release.yaml` — `timeout: 15m` (kept)

## Trade-offs

- **Pro:** True "default if not set" semantics per field
- **Pro:** Follows established Kyverno pattern (PSS policy uses same `+(anchor)` syntax)
- **Pro:** Removes complex nested Flux patch indirection
- **Con:** Kyverno dependency for HelmRelease defaults (already running)
