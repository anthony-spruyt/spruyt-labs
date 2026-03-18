# VPA Workload Rollout Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add VerticalPodAutoscaler objects to every workload in the cluster so the VPA recommender can generate resource recommendations.

**Architecture:** VPA CRDs move to Talos `extraManifests` for bootstrap safety. Each app gets a `vpa.yaml` in its `app/` directory with `updateMode: "Off"` and per-container policies derived from current requests/limits. Documentation updated so future workloads include VPA.

**Tech Stack:** Kubernetes VPA v1, Talos Linux extraManifests, FluxCD Kustomizations, cowboysysop Helm chart

**Spec:** `docs/superpowers/specs/2026-03-18-vpa-workload-rollout-design.md`
**Issue:** [#694](https://github.com/anthony-spruyt/spruyt-labs/issues/694)

---

## Apps Without Workloads (VPA Not Applicable)

These apps have no Deployment/StatefulSet/DaemonSet and cannot be targeted by VPA:

| App | Reason |
|-----|--------|
| `kyverno/policies` | ClusterPolicy resources only |
| `kube-system/etcd-defrag` | CronJob only |
| `kube-system/hubble-sso` | RBAC resources only |
| `flux-system/flux-receivers` | Receiver resource only |
| `flux-system/flux-sso` | RBAC/NetworkPolicy resources only |
| `observability/victoria-metrics-secret-writer` | Job only |
| `dev-debug` | Empty namespace |
| `kube-node-lease` | No workloads |
| `kube-public` | No workloads |

---

## Chunk 1: Infrastructure Changes

### Task 1: Move VPA CRDs to Talos Extra Manifests

**Files:**
- Modify: `talos/patches/control-plane/extra-manifests.yaml`
- Modify: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml`
- Modify: `cluster/apps/vpa-system/vertical-pod-autoscaler/ks.yaml`
- Modify: `cluster/apps/spegel/spegel/ks.yaml`

- [ ] **Step 1: Add VPA CRD URL to Talos extra manifests**

Append to `talos/patches/control-plane/extra-manifests.yaml` after the last entry:

```yaml
    - # renovate: depName=kubernetes/autoscaler datasource=github-tags versioning=regex:^vertical-pod-autoscaler-(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
      https://raw.githubusercontent.com/kubernetes/autoscaler/vertical-pod-autoscaler-1.6.0/vertical-pod-autoscaler/deploy/vpa-v1-crd-gen.yaml
```

- [ ] **Step 2: Disable CRD installation in VPA Helm chart**

Add to `cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml`:

```yaml
crds:
  # CRDs managed via Talos extraManifests (talos/patches/control-plane/extra-manifests.yaml)
  enabled: false
```

Verify `crds.enabled` is the correct key by checking the cowboysysop chart's upstream values via Context7 or WebFetch.

- [ ] **Step 3: Remove `wait: true` from VPA ks.yaml**

In `cluster/apps/vpa-system/vertical-pod-autoscaler/ks.yaml`, remove these lines:

```yaml
  wait: true # Ensures VPA CRDs are registered before dependents (e.g., Spegel) reconcile
```

- [ ] **Step 4: Remove Spegel's VPA dependency**

In `cluster/apps/spegel/spegel/ks.yaml`, remove:

```yaml
  dependsOn:
    - name: vertical-pod-autoscaler
```

- [ ] **Step 5: Update existing Spegel VPA to new convention**

Read Spegel's `values.yaml` for current requests/limits:
- requests: `cpu: 200m, memory: 128Mi`
- limits: `memory: 128Mi` (no CPU limit)

Query cluster for actual container name: use `mcp__kubernetes__get_daemonsets` for namespace `spegel`.

Replace `cluster/apps/spegel/spegel/app/vpa.yaml` with:

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: spegel
spec:
  targetRef:
    apiVersion: apps/v1
    kind: DaemonSet
    name: spegel
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: <verified-container-name>
        minAllowed:
          cpu: 200m
          memory: 128Mi
        maxAllowed:
          memory: 128Mi
```

- [ ] **Step 6: Commit infrastructure changes**

```bash
git add talos/patches/control-plane/extra-manifests.yaml \
  cluster/apps/vpa-system/vertical-pod-autoscaler/app/values.yaml \
  cluster/apps/vpa-system/vertical-pod-autoscaler/ks.yaml \
  cluster/apps/spegel/spegel/ks.yaml \
  cluster/apps/spegel/spegel/app/vpa.yaml
git commit -m "feat(vpa): move CRDs to Talos extraManifests and update Spegel VPA

Move VPA CRD installation from Helm chart to Talos extraManifests for
bootstrap safety. Disable chart CRD install, remove wait and dependsOn
that existed solely for CRD ordering. Update Spegel VPA to use
requests/limits convention.

Ref #694"
```

---

## Chunk 2: VPA Objects — kube-system & System Namespaces

For each app below, the implementer must:
1. Query the cluster via MCP tools to get the actual workload name(s) and container name(s)
2. Read `values.yaml` for resource requests/limits
3. Create `vpa.yaml` in the app's `app/` directory
4. Add `vpa.yaml` to the app's `app/kustomization.yaml` resources list

### Task 2: kube-system workloads

**Files:**
- Create: `cluster/apps/kube-system/cilium/app/vpa.yaml`
- Create: `cluster/apps/kube-system/descheduler/app/vpa.yaml`
- Create: `cluster/apps/kube-system/snapshot-controller/app/vpa.yaml`
- Modify: `cluster/apps/kube-system/cilium/app/kustomization.yaml`
- Modify: `cluster/apps/kube-system/descheduler/app/kustomization.yaml`
- Modify: `cluster/apps/kube-system/snapshot-controller/app/kustomization.yaml`

- [ ] **Step 1: Query cluster for kube-system workloads**

Use `mcp__kubernetes__get_deployments`, `mcp__kubernetes__get_daemonsets` for namespace `kube-system`.
Record each workload's name, kind, container names.

- [ ] **Step 2: Read values.yaml files for resource specs**

Read:
- `cluster/apps/kube-system/cilium/app/values.yaml` — Cilium has multiple components (agent DaemonSet, operator Deployment)
- `cluster/apps/kube-system/descheduler/app/values.yaml`
- `cluster/apps/kube-system/snapshot-controller/app/` — raw manifests, read the deployment YAML for resource specs

- [ ] **Step 3: Create VPA files**

For each workload, create `vpa.yaml` using the template from the spec. Per-container policies with `minAllowed` = requests, `maxAllowed` = limits. Omit `maxAllowed.cpu` when no CPU limit is set.

Cilium will have multiple VPA entries in one file (one for the agent DaemonSet, one for the operator Deployment).

- [ ] **Step 4: Add vpa.yaml to each kustomization.yaml resources list**

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/kube-system/cilium/app/vpa.yaml \
  cluster/apps/kube-system/cilium/app/kustomization.yaml \
  cluster/apps/kube-system/descheduler/app/vpa.yaml \
  cluster/apps/kube-system/descheduler/app/kustomization.yaml \
  cluster/apps/kube-system/snapshot-controller/app/vpa.yaml \
  cluster/apps/kube-system/snapshot-controller/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for kube-system workloads

Add VPA recommendation-only objects for Cilium (agent + operator),
descheduler, and snapshot-controller.

Ref #694"
```

### Task 3: VPA system self-monitoring

**Files:**
- Create: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/vpa.yaml`
- Modify: `cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomization.yaml`

- [ ] **Step 1: Query cluster for VPA workloads**

Use `mcp__kubernetes__get_deployments` for namespace `vpa-system`.
The chart deploys: admission-controller, recommender, updater (all Deployments).

- [ ] **Step 2: Create VPA file with three entries**

From `values.yaml`:
- admissionController: requests `cpu: 50m, memory: 256Mi`, limits `memory: 512Mi`
- recommender: requests `cpu: 50m, memory: 512Mi`, limits `memory: 1024Mi`
- updater: requests `cpu: 50m, memory: 512Mi`, limits `memory: 1024Mi`

Create `vpa.yaml` with three VPA entries (one per Deployment). Omit `maxAllowed.cpu` (no CPU limits set).

- [ ] **Step 3: Add vpa.yaml to kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/vpa-system/vertical-pod-autoscaler/app/vpa.yaml \
  cluster/apps/vpa-system/vertical-pod-autoscaler/app/kustomization.yaml
git commit -m "feat(vpa): add VPA self-monitoring for VPA operator components

Ref #694"
```

### Task 4: Flux system workloads

**Files:**
- Create: `cluster/apps/flux-system/flux-operator/app/vpa.yaml`
- Create: `cluster/apps/flux-system/flux-instance/app/vpa.yaml`
- Modify: `cluster/apps/flux-system/flux-operator/app/kustomization.yaml`
- Modify: `cluster/apps/flux-system/flux-instance/app/kustomization.yaml`

- [ ] **Step 1: Query cluster for flux-system workloads**

Use `mcp__kubernetes__get_deployments` for namespace `flux-system`.
flux-instance creates multiple controllers (source-controller, kustomize-controller, helm-controller, notification-controller).

- [ ] **Step 2: Read values.yaml files for resource specs**

- [ ] **Step 3: Create VPA files**

flux-instance will have multiple VPA entries (one per controller Deployment).

- [ ] **Step 4: Add vpa.yaml to each kustomization.yaml**

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/flux-system/flux-operator/app/vpa.yaml \
  cluster/apps/flux-system/flux-operator/app/kustomization.yaml \
  cluster/apps/flux-system/flux-instance/app/vpa.yaml \
  cluster/apps/flux-system/flux-instance/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for Flux system workloads

Ref #694"
```

---

## Chunk 3: VPA Objects — Storage, Networking & Security

### Task 5: Storage workloads (rook-ceph, cnpg, csi-addons)

**Files:**
- Create: `cluster/apps/rook-ceph/rook-ceph-operator/app/vpa.yaml`
- Create: `cluster/apps/rook-ceph/rook-ceph-cluster/app/vpa.yaml`
- Create: `cluster/apps/cnpg-system/cnpg-operator/app/vpa.yaml`
- Create: `cluster/apps/cnpg-system/plugin-barman-cloud/app/vpa.yaml`
- Create: `cluster/apps/csi-addons-system/csi-addons-controller-manager/app/vpa.yaml`
- Modify: each app's `app/kustomization.yaml`

- [ ] **Step 1: Query cluster for storage workloads**

Use MCP tools for namespaces: `rook-ceph`, `cnpg-system`, `csi-addons-system`.
Note: rook-ceph-cluster has many components (mgr, mon, osd, rgw, etc.) — each gets a VPA entry.

- [ ] **Step 2: Read values.yaml for resource specs**

- [ ] **Step 3: Create VPA files and update kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/rook-ceph/rook-ceph-operator/app/vpa.yaml \
  cluster/apps/rook-ceph/rook-ceph-operator/app/kustomization.yaml \
  cluster/apps/rook-ceph/rook-ceph-cluster/app/vpa.yaml \
  cluster/apps/rook-ceph/rook-ceph-cluster/app/kustomization.yaml \
  cluster/apps/cnpg-system/cnpg-operator/app/vpa.yaml \
  cluster/apps/cnpg-system/cnpg-operator/app/kustomization.yaml \
  cluster/apps/cnpg-system/plugin-barman-cloud/app/vpa.yaml \
  cluster/apps/cnpg-system/plugin-barman-cloud/app/kustomization.yaml \
  cluster/apps/csi-addons-system/csi-addons-controller-manager/app/vpa.yaml \
  cluster/apps/csi-addons-system/csi-addons-controller-manager/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for storage workloads

Add VPA for rook-ceph operator and cluster components, CNPG operator
and barman-cloud plugin, and CSI addons controller.

Ref #694"
```

### Task 6: Networking & DNS workloads

**Files:**
- Create: `cluster/apps/traefik/traefik/app/vpa.yaml`
- Create: `cluster/apps/technitium/technitium/app/vpa.yaml`
- Create: `cluster/apps/technitium/technitium-secondary/app/vpa.yaml`
- Create: `cluster/apps/external-dns/external-dns-technitium/app/vpa.yaml`
- Create: `cluster/apps/cloudflare-system/cloudflared/app/vpa.yaml`
- Create: `cluster/apps/chrony/chrony/app/vpa.yaml`
- Modify: each app's `app/kustomization.yaml`

- [ ] **Step 1: Query cluster for networking workloads**

Use MCP tools for namespaces: `traefik`, `technitium`, `external-dns`, `cloudflare-system`, `chrony`.

- [ ] **Step 2: Read values.yaml for resource specs**

- [ ] **Step 3: Create VPA files and update kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/traefik/traefik/app/vpa.yaml \
  cluster/apps/traefik/traefik/app/kustomization.yaml \
  cluster/apps/technitium/technitium/app/vpa.yaml \
  cluster/apps/technitium/technitium/app/kustomization.yaml \
  cluster/apps/technitium/technitium-secondary/app/vpa.yaml \
  cluster/apps/technitium/technitium-secondary/app/kustomization.yaml \
  cluster/apps/external-dns/external-dns-technitium/app/vpa.yaml \
  cluster/apps/external-dns/external-dns-technitium/app/kustomization.yaml \
  cluster/apps/cloudflare-system/cloudflared/app/vpa.yaml \
  cluster/apps/cloudflare-system/cloudflared/app/kustomization.yaml \
  cluster/apps/chrony/chrony/app/vpa.yaml \
  cluster/apps/chrony/chrony/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for networking and DNS workloads

Add VPA for Traefik, Technitium (primary + secondary), external-dns,
cloudflared, and chrony.

Ref #694"
```

### Task 7: Security workloads

**Files:**
- Create: `cluster/apps/kyverno/kyverno/app/vpa.yaml`
- Create: `cluster/apps/cert-manager/cert-manager/app/vpa.yaml`
- Create: `cluster/apps/authentik-system/authentik/app/vpa.yaml`
- Create: `cluster/apps/external-secrets/external-secrets/app/vpa.yaml`
- Create: `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/vpa.yaml`
- Create: `cluster/apps/falco-system/falco/app/vpa.yaml`
- Modify: each app's `app/kustomization.yaml`

- [ ] **Step 1: Query cluster for security workloads**

Use MCP tools for namespaces: `kyverno`, `cert-manager`, `authentik-system`, `external-secrets`, `kubelet-csr-approver`, `falco-system`.
Note: Kyverno and cert-manager may have multiple Deployments (admission controller, cleanup controller, etc.).

- [ ] **Step 2: Read values.yaml for resource specs**

- [ ] **Step 3: Create VPA files and update kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/kyverno/kyverno/app/vpa.yaml \
  cluster/apps/kyverno/kyverno/app/kustomization.yaml \
  cluster/apps/cert-manager/cert-manager/app/vpa.yaml \
  cluster/apps/cert-manager/cert-manager/app/kustomization.yaml \
  cluster/apps/authentik-system/authentik/app/vpa.yaml \
  cluster/apps/authentik-system/authentik/app/kustomization.yaml \
  cluster/apps/external-secrets/external-secrets/app/vpa.yaml \
  cluster/apps/external-secrets/external-secrets/app/kustomization.yaml \
  cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/vpa.yaml \
  cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/kustomization.yaml \
  cluster/apps/falco-system/falco/app/vpa.yaml \
  cluster/apps/falco-system/falco/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for security workloads

Add VPA for Kyverno, cert-manager, Authentik, external-secrets,
kubelet-csr-approver, and Falco.

Ref #694"
```

---

## Chunk 4: VPA Objects — Observability, Apps & Utilities

### Task 8: Observability workloads

**Files:**
- Create: `cluster/apps/observability/victoria-metrics-operator/app/vpa.yaml`
- Create: `cluster/apps/observability/victoria-metrics-k8s-stack/app/vpa.yaml`
- Create: `cluster/apps/observability/victoria-logs-single/app/vpa.yaml`
- Create: `cluster/apps/observability/mcp-victoriametrics/app/vpa.yaml`
- Create: `cluster/apps/reloader/reloader/app/vpa.yaml`
- Create: `cluster/apps/headlamp-system/headlamp/app/vpa.yaml`
- Modify: each app's `app/kustomization.yaml`

- [ ] **Step 1: Query cluster for observability workloads**

Use MCP tools for namespaces: `observability`, `reloader`, `headlamp-system`.
Note: victoria-metrics-k8s-stack deploys multiple components (vmsingle, vmagent, vmalert, alertmanager, grafana).

- [ ] **Step 2: Read values.yaml for resource specs**

- [ ] **Step 3: Create VPA files and update kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/observability/victoria-metrics-operator/app/vpa.yaml \
  cluster/apps/observability/victoria-metrics-operator/app/kustomization.yaml \
  cluster/apps/observability/victoria-metrics-k8s-stack/app/vpa.yaml \
  cluster/apps/observability/victoria-metrics-k8s-stack/app/kustomization.yaml \
  cluster/apps/observability/victoria-logs-single/app/vpa.yaml \
  cluster/apps/observability/victoria-logs-single/app/kustomization.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/vpa.yaml \
  cluster/apps/observability/mcp-victoriametrics/app/kustomization.yaml \
  cluster/apps/reloader/reloader/app/vpa.yaml \
  cluster/apps/reloader/reloader/app/kustomization.yaml \
  cluster/apps/headlamp-system/headlamp/app/vpa.yaml \
  cluster/apps/headlamp-system/headlamp/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for observability workloads

Add VPA for VictoriaMetrics stack (operator, k8s-stack, logs, MCP),
Reloader, and Headlamp.

Ref #694"
```

### Task 9: Application workloads

**Files:**
- Create: `cluster/apps/firefly-iii/firefly-iii/app/vpa.yaml`
- Create: `cluster/apps/firefly-iii/firemerge/app/vpa.yaml`
- Create: `cluster/apps/vaultwarden/vaultwarden/app/vpa.yaml`
- Create: `cluster/apps/mosquitto/mosquitto/app/vpa.yaml`
- Create: `cluster/apps/n8n-system/n8n/app/vpa.yaml`
- Create: `cluster/apps/foundryvtt/foundryvtt/app/vpa.yaml`
- Create: `cluster/apps/qdrant-system/qdrant/app/vpa.yaml`
- Create: `cluster/apps/minecraft/crafty-controller/app/vpa.yaml`
- Create: `cluster/apps/minecraft/bedrock-connect/app/vpa.yaml`
- Create: `cluster/apps/redisinsight/redisinsight/app/vpa.yaml`
- Modify: each app's `app/kustomization.yaml`

- [ ] **Step 1: Query cluster for application workloads**

Use MCP tools for namespaces: `firefly-iii`, `vaultwarden`, `mosquitto`, `n8n-system`, `foundryvtt`, `qdrant-system`, `minecraft`, `redisinsight`.

- [ ] **Step 2: Read values.yaml for resource specs**

- [ ] **Step 3: Create VPA files and update kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/firefly-iii/firefly-iii/app/vpa.yaml \
  cluster/apps/firefly-iii/firefly-iii/app/kustomization.yaml \
  cluster/apps/firefly-iii/firemerge/app/vpa.yaml \
  cluster/apps/firefly-iii/firemerge/app/kustomization.yaml \
  cluster/apps/vaultwarden/vaultwarden/app/vpa.yaml \
  cluster/apps/vaultwarden/vaultwarden/app/kustomization.yaml \
  cluster/apps/mosquitto/mosquitto/app/vpa.yaml \
  cluster/apps/mosquitto/mosquitto/app/kustomization.yaml \
  cluster/apps/n8n-system/n8n/app/vpa.yaml \
  cluster/apps/n8n-system/n8n/app/kustomization.yaml \
  cluster/apps/foundryvtt/foundryvtt/app/vpa.yaml \
  cluster/apps/foundryvtt/foundryvtt/app/kustomization.yaml \
  cluster/apps/qdrant-system/qdrant/app/vpa.yaml \
  cluster/apps/qdrant-system/qdrant/app/kustomization.yaml \
  cluster/apps/minecraft/crafty-controller/app/vpa.yaml \
  cluster/apps/minecraft/crafty-controller/app/kustomization.yaml \
  cluster/apps/minecraft/bedrock-connect/app/vpa.yaml \
  cluster/apps/minecraft/bedrock-connect/app/kustomization.yaml \
  cluster/apps/redisinsight/redisinsight/app/vpa.yaml \
  cluster/apps/redisinsight/redisinsight/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for application workloads

Add VPA for Firefly III, Firemerge, Vaultwarden, Mosquitto, n8n,
FoundryVTT, Qdrant, Crafty Controller, Bedrock Connect, and
RedisInsight.

Ref #694"
```

### Task 10: Utility & infrastructure workloads

**Files:**
- Create: `cluster/apps/irq-balance/irq-balance-e2/app/vpa.yaml`
- Create: `cluster/apps/irq-balance/irq-balance-ms-01/app/vpa.yaml`
- Create: `cluster/apps/kubectl-mcp/kubectl-mcp-server/app/vpa.yaml`
- Create: `cluster/apps/nut-system/nut-server/app/vpa.yaml`
- Create: `cluster/apps/nut-system/shutdown-orchestrator/app/vpa.yaml`
- Create: `cluster/apps/openclaw/openclaw/app/vpa.yaml`
- Create: `cluster/apps/valkey-system/valkey/app/vpa.yaml`
- Create: `cluster/apps/velero/velero/app/vpa.yaml`
- Create: `cluster/apps/sungather/sungather/app/vpa.yaml`
- Create: `cluster/apps/whoami/whoami/app/vpa.yaml`
- Modify: each app's `app/kustomization.yaml`

- [ ] **Step 1: Query cluster for utility workloads**

Use MCP tools for namespaces: `irq-balance`, `kubectl-mcp`, `nut-system`, `openclaw`, `valkey-system`, `velero`, `sungather`, `whoami`.

- [ ] **Step 2: Read values.yaml for resource specs**

- [ ] **Step 3: Create VPA files and update kustomization.yaml**

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/irq-balance/irq-balance-e2/app/vpa.yaml \
  cluster/apps/irq-balance/irq-balance-e2/app/kustomization.yaml \
  cluster/apps/irq-balance/irq-balance-ms-01/app/vpa.yaml \
  cluster/apps/irq-balance/irq-balance-ms-01/app/kustomization.yaml \
  cluster/apps/kubectl-mcp/kubectl-mcp-server/app/vpa.yaml \
  cluster/apps/kubectl-mcp/kubectl-mcp-server/app/kustomization.yaml \
  cluster/apps/nut-system/nut-server/app/vpa.yaml \
  cluster/apps/nut-system/nut-server/app/kustomization.yaml \
  cluster/apps/nut-system/shutdown-orchestrator/app/vpa.yaml \
  cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml \
  cluster/apps/openclaw/openclaw/app/vpa.yaml \
  cluster/apps/openclaw/openclaw/app/kustomization.yaml \
  cluster/apps/valkey-system/valkey/app/vpa.yaml \
  cluster/apps/valkey-system/valkey/app/kustomization.yaml \
  cluster/apps/velero/velero/app/vpa.yaml \
  cluster/apps/velero/velero/app/kustomization.yaml \
  cluster/apps/sungather/sungather/app/vpa.yaml \
  cluster/apps/sungather/sungather/app/kustomization.yaml \
  cluster/apps/whoami/whoami/app/vpa.yaml \
  cluster/apps/whoami/whoami/app/kustomization.yaml
git commit -m "feat(vpa): add VPA objects for utility and infrastructure workloads

Add VPA for irq-balance, kubectl-mcp-server, NUT server,
shutdown-orchestrator, OpenClaw, Valkey, Velero, Sungather, and whoami.

Ref #694"
```

---

## Chunk 5: Documentation & Validation

### Task 11: Update patterns.md documentation

**Files:**
- Modify: `.claude/rules/patterns.md`

- [ ] **Step 1: Add vpa.yaml to app structure tree**

In `.claude/rules/patterns.md`, update the App Structure tree to include `vpa.yaml`:

```text
cluster/apps/<namespace>/
├── namespace.yaml          # Namespace with PSA labels
├── kustomization.yaml      # References namespace + app ks.yaml files
├── <app>/                  # Single app
│   ├── ks.yaml
│   ├── app/
│   │   ├── kustomization.yaml
│   │   ├── release.yaml        # HelmRelease
│   │   ├── values.yaml         # Helm values
│   │   ├── vpa.yaml            # VPA (recommendation-only)
│   │   └── *-secrets.sops.yaml # Encrypted secrets
│   └── <optional>/         # Optional dependent resources (e.g., ingress/)
```

- [ ] **Step 2: Add VPA section**

Add after the "Helm Values" section:

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

- [ ] **Step 3: Commit**

```bash
git add .claude/rules/patterns.md
git commit -m "docs(vpa): add VPA guidance to cluster patterns documentation

Ref #694"
```

### Task 12: Run qa-validator

- [ ] **Step 1: Run qa-validator agent**

Dispatch the qa-validator agent to validate all changes before final commit/squash.

- [ ] **Step 2: Fix any issues found**

If qa-validator reports issues, fix them and re-run.

### Task 13: Final verification

- [ ] **Step 1: Verify all workloads have VPA coverage**

Run a check: for every `app/kustomization.yaml` that references a `release.yaml` or a Deployment/StatefulSet/DaemonSet manifest, verify a `vpa.yaml` is also in the resources list. Exclude the known non-workload apps.

- [ ] **Step 2: Verify no circular dependencies**

Confirm no `ks.yaml` has `dependsOn: vertical-pod-autoscaler` (except none should remain).

- [ ] **Step 3: Update issue #694**

Post a summary comment on #694 listing all VPA objects created and any notes.

---

## Parallelization Guide

Tasks can be parallelized as follows:

| Group | Tasks | Dependencies |
|-------|-------|-------------|
| **Sequential first** | Task 1 | Must complete first (infrastructure changes) |
| **Parallel batch 1** | Tasks 2, 3, 4 | All independent after Task 1 |
| **Parallel batch 2** | Tasks 5, 6, 7 | All independent after Task 1 |
| **Parallel batch 3** | Tasks 8, 9, 10 | All independent after Task 1 |
| **Sequential last** | Tasks 11, 12, 13 | After all VPA files created |

Within each parallel batch, tasks are independent and can run concurrently via subagents. Each subagent must query the cluster for workload names/containers and read values.yaml files — these are read-only operations that don't conflict.

**Important for subagents:**
- Each subagent must `git add` only the specific files it created/modified. Never use `git add -A`, `git add .`, or glob patterns.
- File creation is parallelizable, but commits must be serialized — only one agent can commit at a time to avoid conflicts on the branch tip. Subagents should create files and stage them, then commits are made sequentially.
