# VPA Workload Rollout Design

**Issue:** [#694](https://github.com/anthony-spruyt/spruyt-labs/issues/694) — feat(vpa): add VPA objects to all workloads
**Blocks:** [#692](https://github.com/anthony-spruyt/spruyt-labs/issues/692) — feat(vpa): act on VPA recommendations
**Date:** 2026-03-18

## Problem

VPA was deployed in #674 but only Spegel has a VPA object. The recommender only generates `.status.recommendation` on existing VPA objects, so #692 is blocked — there are no recommendations to review for the rest of the cluster.

## Design

### 1. VPA CRDs via Talos Extra Manifests

Move VPA CRD installation from the Helm chart to Talos `extraManifests` so CRDs are available at cluster bootstrap, before Flux reconciles. This eliminates circular dependency concerns — any app can include a `vpa.yaml` without depending on the VPA operator kustomization.

**Add to `talos/patches/control-plane/extra-manifests.yaml`:**

```yaml
- # renovate: depName=kubernetes/autoscaler datasource=github-tags versioning=regex:^vertical-pod-autoscaler-(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
  https://raw.githubusercontent.com/kubernetes/autoscaler/vertical-pod-autoscaler-1.6.0/vertical-pod-autoscaler/deploy/vpa-v1-crd-gen.yaml
```

**Disable CRD installation in the Helm chart** by adding to `cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml`:

```yaml
crds:
  # CRDs managed via Talos extraManifests (talos/patches/control-plane/extra-manifests.yaml)
  enabled: false
```

**Remove `wait: true` and its comment** from the VPA `ks.yaml` — CRD ordering is no longer a concern, and once Spegel's `dependsOn: vertical-pod-autoscaler` is removed (see Section 3), nothing depends on VPA being ready.

**Remove `dependsOn: vertical-pod-autoscaler` from Spegel's `ks.yaml`** — This dependency existed solely for CRD ordering. With CRDs at the Talos level, it is unnecessary. New apps with `vpa.yaml` must NOT add `dependsOn: vertical-pod-autoscaler`.

**CRD version coordination:** The Talos extraManifests CRD version (`kubernetes/autoscaler` tags) and the cowboysysop Helm chart version are independently versioned. Renovate tracks both — if the chart upgrades and expects newer CRD fields, update the extraManifests URL to match. Add a comment in the Helm values referencing the extraManifests entry:

### 2. VPA Object Per Workload

Add a `vpa.yaml` file to each app's `app/` directory, following the existing Spegel pattern.

**Template:**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: <workload-name>
spec:
  targetRef:
    apiVersion: apps/v1
    kind: <Deployment|StatefulSet|DaemonSet>
    name: <actual-resource-name-from-cluster>
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: <container-name>
        minAllowed:
          cpu: <current-request-cpu>
          memory: <current-request-memory>
        maxAllowed:
          cpu: <current-limit-cpu>
          memory: <current-limit-memory>
```

**Conventions:**

- `updateMode: "Off"` — recommendation-only, no automatic updates
- Per-container policies — no `"*"` wildcards. Only include containers defined in the app's own chart/manifest; exclude externally-injected sidecars
- `minAllowed` = current resource requests from `values.yaml`
- `maxAllowed` = current resource limits from `values.yaml`
- When CPU limits are not set (common pattern — only memory limits), omit `maxAllowed.cpu` to let the recommender provide unconstrained CPU recommendations
- When a container has no resource requests or limits at all, omit it from `containerPolicies` — the recommender will still generate recommendations for it using VPA defaults
- `metadata.name` on the VPA object does not need to match `targetRef.name` — it just needs to be unique in the namespace. Use the workload name for clarity
- `targetRef.name` = actual Deployment/StatefulSet/DaemonSet name queried from cluster via MCP tools
- Schema annotation on every file
- Multi-workload apps (e.g., chart creates both a Deployment and a DaemonSet) get multiple VPA entries in the same `vpa.yaml`

**Scope:** Every workload, no exclusions. `Off` mode is zero-risk — purely observational.

### 3. Kustomization and Dependency Changes

Each `vpa.yaml` is added to its app's `app/kustomization.yaml` resources list. No Flux `dependsOn` changes needed since CRDs are available at bootstrap via Talos.

**Remove Spegel's VPA dependency:** Delete `dependsOn: [{name: vertical-pod-autoscaler}]` from `cluster/apps/spegel/spegel/ks.yaml`. This dependency existed solely for CRD ordering, which is now handled at the Talos level.

### 4. Update Existing Spegel VPA

Update `cluster/apps/spegel/spegel/app/vpa.yaml` to match the new convention.

Current bounds: `cpu: 2m-10m, memory: 24Mi-128Mi`
Spegel values: requests `cpu: 200m, memory: 128Mi`, limits `memory: 128Mi` (no CPU limit)

Updated VPA should have:
- `minAllowed`: `cpu: 200m, memory: 128Mi`
- `maxAllowed`: `memory: 128Mi` (omit CPU since no CPU limit is set)
- Verify container name and targetRef against the cluster

### 5. Documentation Updates

**Update `.claude/rules/patterns.md`:**

Add `vpa.yaml` to the app structure tree:

```text
cluster/apps/<namespace>/
├── <app>/
│   ├── ks.yaml
│   ├── app/
│   │   ├── kustomization.yaml
│   │   ├── release.yaml
│   │   ├── values.yaml
│   │   ├── vpa.yaml             # VPA (recommendation-only)
│   │   └── *-secrets.sops.yaml
```

Add a new VPA section:

```markdown
## VPA (Vertical Pod Autoscaler)

Every workload must include a `vpa.yaml` in its `app/` directory.

- `updateMode: "Off"` — recommendation-only
- Per-container `containerPolicies` (no wildcards)
- `minAllowed` = current resource requests
- `maxAllowed` = current resource limits (omit CPU if no CPU limit is set)
- Containers with no resource specs: omit from `containerPolicies`
- `targetRef.name` must match the actual resource name in the cluster
- No `dependsOn: vertical-pod-autoscaler` needed — CRDs are installed via Talos `extraManifests`
- Schema: `https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json`

If a recommendation hits a boundary, adjust `minAllowed`/`maxAllowed` and recheck.
```

## Implementation Notes

- Query cluster via MCP tools (`get_deployments`, `get_statefulsets`, `get_daemonsets`) to discover actual resource names and container names per namespace
- Cross-reference with `values.yaml` for current requests/limits
- VPA objects for the VPA operator's own components (recommender, updater, admission-controller) are included — no circular dependency since CRDs are at the Talos level

## Out of Scope

- Enabling `updateMode: "Auto"` on any workload (that's #692)
- Adjusting resource requests/limits based on recommendations (that's #692)
- VPA alerting or dashboards
