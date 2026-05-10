# ServiceAccount Token Automount Hardening

**Issue**: #576 **Date**: 2026-05-10 **Status**: Draft

## Goal

Prevent unnecessary Kubernetes API token mounting across all workloads. Every pod must explicitly declare whether it needs a token (`automountServiceAccountToken: true`) or not (`automountServiceAccountToken: false`). Kyverno enforces this going forward.

## Strategy

1. **Fix all existing workloads** — add explicit `automountServiceAccountToken` to every pod spec we control
1. **Kyverno validate (enforce)** — blocks new pods missing the field
1. **Kyverno mutate (targeted)** — injects `false` on uncontrollable pods (Authentik outposts) so they pass validation
1. **HelmRelease SA hardening** — creates dedicated SAs for workloads currently using `default` SA

## Layer 1: Fix All Existing Workloads

### Raw Manifests — Add `automountServiceAccountToken: true`

These workloads use kubectl/API and need the token:

| File                                                                        | Workload                         |
| --------------------------------------------------------------------------- | -------------------------------- |
| `authentik-system/authentik/app/oauth-secret-rotation/cronjob.yaml`         | oauth-secret-rotation            |
| `github-system/github-token-rotation/app/cronjob.yaml`                      | github-token-rotation            |
| `github-system/bot-ssh-key-rotation/app/cronjob.yaml`                       | bot-ssh-key-rotation             |
| `coder-workspaces/ssh-key-rotation/app/cronjob.yaml`                        | ssh-key-rotation                 |
| `csi-addons-system/csi-addons-controller-manager/app/restart-cronjob.yaml`  | csi-addons-restart               |
| `csi-addons-system/csi-addons-controller-manager/app/setup-controller.yaml` | csi-addons-controller-manager    |
| `kube-system/snapshot-controller/app/setup-snapshot-controller.yaml`        | snapshot-controller              |
| `observability/victoria-metrics-secret-writer/app/etcd-secret-writer.yaml`  | etcd-secret-writer (already set) |

### Raw Manifests — Add `automountServiceAccountToken: false`

These workloads don't use the Kubernetes API:

| File                                              | Workload                  |
| ------------------------------------------------- | ------------------------- |
| `nexus-system/nexus/app/provision-repos-job.yaml` | nexus-provision-repos     |
| `kube-system/etcd-defrag/app/cronjob.yaml`        | etcd-defrag (already set) |

### HelmRelease Values — Set `automountServiceAccountToken: false`

These workloads don't need API access and should declare it via chart values or postRenderers:

| HelmRelease              | Namespace        | Method                                                      |
| ------------------------ | ---------------- | ----------------------------------------------------------- |
| `authentik`              | authentik-system | `server.serviceAccountName: authentik` + postRenderer patch |
| `firefly-iii`            | firefly-iii      | postRenderer patches on Deployment + CronJob                |
| `victoria-logs-single`   | observability    | `serviceAccount.create: true`, `automountToken: false`      |
| `victoria-traces-single` | observability    | `serviceAccount.create: true`, `automountToken: false`      |

### HelmRelease Values — Verify Explicit `automountServiceAccountToken`

These are Helm-managed workloads with dedicated SAs. During implementation, verify each chart already sets the field in its pod templates. If not, add via values or postRenderer:

| HelmRelease             | Needs API | Expected Setting |
| ----------------------- | --------- | ---------------- |
| cert-manager            | yes       | `true`           |
| external-secrets        | yes       | `true`           |
| cnpg-operator           | yes       | `true`           |
| reloader                | yes       | `true`           |
| kyverno                 | yes       | `true`           |
| cilium                  | yes       | `true`           |
| velero                  | yes       | `true`           |
| rook-ceph-operator      | yes       | `true`           |
| external-dns-technitium | yes       | `true`           |
| descheduler             | yes       | `true`           |
| metrics-server          | yes       | `true`           |
| kubelet-csr-approver    | yes       | `true`           |
| vpa                     | yes       | `true`           |
| flux-operator           | yes       | `true`           |
| falco                   | yes       | `true`           |
| traefik                 | no        | `false`          |
| cloudflared             | no        | `false`          |
| mosquitto               | no        | `false`          |
| sungather               | no        | `false`          |
| whoami                  | no        | `false`          |
| bedrock-connect         | no        | `false`          |
| crafty-controller       | no        | `false`          |
| foundryvtt              | no        | `false`          |
| redisinsight            | no        | `false`          |
| technitium              | no        | `false`          |
| technitium-secondary    | no        | `false`          |
| vaultwarden             | no        | `false`          |
| nut-server              | no        | `false`          |
| n8n                     | no        | `false`          |
| qdrant                  | no        | `false`          |
| brave-search-mcp        | no        | `false`          |
| mcp-victoriametrics     | no        | `false`          |
| n8n-mcp-server          | no        | `false`          |
| headlamp                | yes       | `true`           |
| agent-queue-worker      | no        | `false`          |
| agent-valkey            | no        | `false`          |
| valkey                  | no        | `false`          |
| chrony                  | no        | `false`          |
| nexus                   | no        | `false`          |
| shutdown-orchestrator   | yes       | `true`           |
| irq-balance             | no        | `false`          |
| spegel                  | yes       | `true`           |
| coder                   | yes       | `true`           |

During implementation, verify each chart's actual behavior. Some charts already set the field in their templates (no action needed). Others need values or postRenderers.

## Layer 2: Kyverno Validate Policy (Enforce)

**File**: `cluster/apps/kyverno/policies/app/require-explicit-automount.yaml`

**Kind**: `ClusterPolicy` (validate, enforce)

**Target**: Pods

**Rule**: `spec.automountServiceAccountToken` must be explicitly set (any value). Rejects pods where the field is absent.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-explicit-automount
  annotations:
    policies.kyverno.io/title: Require Explicit automountServiceAccountToken
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Requires all pods to explicitly declare automountServiceAccountToken
      (true or false). Forces authors to make a conscious decision about
      API token mounting.
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-automount-field
      match:
        any:
          - resources:
              kinds:
                - Pod
              operations:
                - CREATE
                - UPDATE
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kube-public
                - kube-node-lease
      validate:
        message: >-
          Pod {{request.object.metadata.name}} in namespace
          {{request.object.metadata.namespace}} must explicitly set
          spec.automountServiceAccountToken to true or false.
        deny:
          conditions:
            any:
              - key: "{{ request.object.spec.automountServiceAccountToken | type(@) }}"
                operator: NotEquals
                value: "boolean"
```

> **Why `type(@)` instead of `|| 'unset'`:** JMESPath treats `false` as falsy, so `false || 'unset'` evaluates to `'unset'` — incorrectly denying pods with `automountServiceAccountToken: false`. The `type()` function returns `"boolean"` for both `true` and `false`, and `"null"` for absent fields.

**Namespace exclusions** (minimal):

- `kube-system` — static pods and system controllers we don't control
- `kube-public` — system namespace
- `kube-node-lease` — system namespace

All other namespaces are covered. HelmReleases that already set the field pass without changes. Those that don't will be fixed in Layer 1.

## Layer 3: Kyverno Mutate Policy (Targeted Exceptions)

**File**: `cluster/apps/kyverno/policies/app/inject-automount-false-exceptions.yaml`

**Kind**: `ClusterPolicy` (mutate)

**Target**: Pods created by Authentik outpost controller (we cannot modify their specs).

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: inject-automount-false-exceptions
  annotations:
    policies.kyverno.io/title: Inject automountServiceAccountToken for Uncontrollable Workloads
    policies.kyverno.io/category: Security
    policies.kyverno.io/severity: low
    policies.kyverno.io/subject: Pod
    policies.kyverno.io/description: >-
      Injects automountServiceAccountToken: false on pods created by controllers
      we cannot configure (Authentik outposts). Ensures they pass the
      require-explicit-automount validation policy.
spec:
  background: false
  rules:
    - name: inject-automount-authentik-outposts
      match:
        any:
          - resources:
              kinds:
                - Pod
              operations:
                - CREATE
      preconditions:
        all:
          - key: "{{request.object.metadata.labels.\"app.kubernetes.io/managed-by\" || ''}}"
            operator: Equals
            value: goauthentik.io
      mutate:
        patchStrategicMerge:
          spec:
            +(automountServiceAccountToken): false
```

Matches pods with label `app.kubernetes.io/managed-by: goauthentik.io` — the label Authentik controller sets on outpost pods. The `+(field)` anchor ensures we only inject if not already set.

Mutate rules fire BEFORE validate rules in Kyverno's admission pipeline, so injected pods pass validation.

## Layer 4: HelmRelease SA Hardening

### authentik (`authentik-system`)

**Current state**: `authentik-worker` uses SA `authentik` (chart-created). `authentik-server` uses SA `default` because `server.serviceAccountName` defaults to nil.

**Action**:

1. Set `server.serviceAccountName: authentik` in values (reuse chart-created SA)
1. PostRenderer patch on server Deployment: `automountServiceAccountToken: false`

### firefly-iii (`firefly-iii`)

**Current state**: Deployment and CronJob pods use `default` SA. Chart has no SA configuration.

**Action**: Add to EXISTING `postRenderers[0].kustomize.patches` array in `release.yaml`:

```yaml
- target:
    kind: Deployment
    name: firefly-iii
  patch: |
    - op: add
      path: /spec/template/spec/automountServiceAccountToken
      value: false
- target:
    kind: CronJob
    name: firefly-iii-cronjob
  patch: |
    - op: add
      path: /spec/jobTemplate/spec/template/spec/automountServiceAccountToken
      value: false
```

### victoria-logs-single (`observability`)

**Action**: Add to values:

```yaml
serviceAccount:
  create: true
  automountToken: false
```

### victoria-traces-single (`observability`)

**Action**: Add to values:

```yaml
serviceAccount:
  create: true
  automountToken: false
```

## Implementation Notes

### Kustomization Update

Add new policy files to `cluster/apps/kyverno/policies/app/kustomization.yaml`:

```yaml
resources:
  # ... existing entries ...
  - ./require-explicit-automount.yaml
  - ./inject-automount-false-exceptions.yaml
```

### Authentik Outpost Label Verification

Before implementing Layer 3, verify the label Authentik sets on outpost pods:

```bash
kubectl get pods -l app.kubernetes.io/managed-by=goauthentik.io --all-namespaces
```

### HelmRelease Audit Process

Batch-scan all pods first to find which already have the field:

```bash
kubectl get pods -A -o json | jq -r '.items[] | select(.spec.automountServiceAccountToken == null) |
  "\(.metadata.namespace)/\(.metadata.name)"' | sort
```

Then for each HelmRelease that needs fixing:

1. Check if chart exposes a values key for automount (Context7 or upstream values.yaml)
1. If yes: set via values
1. If no: add postRenderer patch

## Rollout Strategy

1. Deploy Layer 1 changes (explicit field on all workloads) — Flux reconciles, pods restart with field set
1. Deploy Layer 3 (mutate exceptions) — Authentik outpost pods get field injected on next restart
1. Deploy Layer 2 (validate enforce) — blocks any new pod missing the field
1. Delete existing Authentik outpost pods (`kubectl delete pod -l app.kubernetes.io/managed-by=goauthentik.io --all-namespaces`) — Authentik controller recreates them, mutate policy injects field on CREATE
1. Deploy Layer 2 (validate enforce) — blocks any new pod missing the field

Steps 2-3 can deploy simultaneously since mutate fires before validate in the admission pipeline. However, existing outpost pods won't have the field until recreated. Deploy mutate first, delete outpost pods, then deploy validate.

## Out of Scope

- **kube-system static pods** (apiserver, controller-manager, scheduler): Use host-path tokens, not SA-mounted. Excluded from policy.
- **ServiceAccount-level `automountServiceAccountToken`**: We set the field at pod-spec level which takes precedence. SA-level settings are a secondary concern.

## Risks

| Risk                                       | Mitigation                                                                           |
| ------------------------------------------ | ------------------------------------------------------------------------------------ |
| Helm chart doesn't expose automount config | PostRenderer patch on Deployment/StatefulSet/CronJob                                 |
| Authentik outpost label changes            | Monitor with PolicyReports; label is stable since Authentik v2023                    |
| Missed workload during audit               | Validate enforce catches it immediately on next pod CREATE                           |
| Rollout ordering causes outpost rejection  | Deploy mutate first, delete outpost pods to trigger recreation, then deploy validate |
| Validate pattern for boolean field         | Using JMESPath existence check (\`                                                   |

## Success Criteria

- Every pod in cluster has explicit `automountServiceAccountToken` (verified via kubectl query)
- Validate policy shows zero violations in PolicyReports
- No pods using `default` SA have `kube-api-access` volume mounted (unless explicitly opted in)
- New deployments without the field are rejected at admission
