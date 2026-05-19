# kyverno-policies - Cluster Policies

## Overview

Custom Kyverno policies for the spruyt-labs homelab. These policies automate resource management and enforce cluster standards.

## Prerequisites

- Kyverno installed and running (dependsOn: kyverno)

## Policies

### add-default-limitrange

Automatically generates a LimitRange in application namespaces to provide default resource requests for containers that don't specify them. This ensures all pods have at least Burstable QoS class.

**Behavior:**

- Triggers on namespace creation
- Creates a LimitRange with default CPU/memory requests
- Synchronized: updates/deletes when policy changes
- Applies to existing namespaces via `generateExisting: true`

**Default Requests Applied:**

| Resource | Default Request |
| -------- | --------------- |
| CPU      | 10m             |
| Memory   | 64Mi            |

**Excluded Namespaces:**

Infrastructure and critical namespaces are excluded to avoid conflicts with their resource configurations:

- Kubernetes system: kube-system, kube-public, kube-node-lease
- GitOps/Policy: flux-system, kyverno
- Core infrastructure: cert-manager, cilium-secrets, cloudflare-system, external-dns, external-secrets, kubelet-csr-approver, reloader, spegel, traefik, velero
- Storage: csi-addons-system, rook-ceph
- Database operators: cnpg-system
- Observability: observability
- System utilities: chrony, irq-balance

### add-helmrelease-defaults

Injects default timeout, install, upgrade, and rollback configuration into HelmReleases that don't already specify them. Uses Kyverno `+(anchor)` syntax so individual HelmReleases can override any field by setting it explicitly.

The `interval` field is **not** managed by this policy — it is set explicitly to `4h` in each HelmRelease manifest (required CRD field).

**Defaults Applied:**

| Field                                           | Default Value        |
| ----------------------------------------------- | -------------------- |
| `spec.timeout`                                  | `10m`                |
| `spec.install.crds`                             | `CreateReplace`      |
| `spec.install.strategy.name`                    | `RetryOnFailure`     |
| `spec.rollback.cleanupOnFail`                   | `true`               |
| `spec.rollback.recreate`                        | `true`               |
| `spec.upgrade.cleanupOnFail`                    | `true`               |
| `spec.upgrade.crds`                             | `CreateReplace`      |
| `spec.upgrade.strategy.name`                    | `RemediateOnFailure` |
| `spec.upgrade.remediation.remediateLastFailure` | `true`               |
| `spec.upgrade.remediation.retries`              | `2`                  |

**Overriding Defaults:**

Set the field explicitly in the HelmRelease spec. For example, to use a longer timeout:

```yaml
spec:
  timeout: 15m  # Overrides the 10m default
```

Current overrides: cilium (`timeout: 2m`), n8n/rook-ceph-cluster (`timeout: 15m`).

### inject-claude-agent-config

Injects configuration into Claude agent pods spawned by n8n. A shared rule injects GitHub bot credentials (gh CLI config, read-only gitconfig), MCP server config, plugin bootstrap volumes, and a `plugin-bootstrap` init container (reads managed-settings.json and user settings.json) into all agent namespaces. Clone rules inject a `plugin-bootstrap-project` init container (after `git-clone`) that
reads project settings.json and settings.local.json to install additional marketplaces and plugins via `claude plugins` CLI. The write namespace additionally receives SSH key and full gitconfig (with commit signing) via strategic merge override. Read and SRE namespaces clone repos via HTTPS using a read-scoped GitHub App token instead of SSH (no SSH key = no push capability).

**Injected resources:** See [`inject-claude-agent-config.yaml`](app/inject-claude-agent-config.yaml) for the full list of volumes, volume mounts, and environment variables.

### set-agent-deadline

Mutates agent pods (labeled `managed-by: n8n-claude-code`) to set `activeDeadlineSeconds` from the `agent-timeout` annotation. Prevents orphaned agent pods from running indefinitely. Excludes persistent agent pods (`app: claude-code-persistent`).

- **Default deadline**: 1740s (29min) if annotation missing
- **Annotation**: `agent-timeout` (seconds)

The timeout annotation is set by the BullMQ worker at pod creation based on per-role job timeouts. See [agent-queue-worker README](../../agent-worker-system/agent-queue-worker/README.md#timeouts) for role timeout values.

### validate-agent-deadline

Safety net for `set-agent-deadline`. Rejects agent pods missing `activeDeadlineSeconds` (Enforce mode). Catches mutation policy failures.

### cleanup-agent-pods

Hourly cleanup policy (`ClusterCleanupPolicy`). Removes completed/failed agent pods that n8n failed to delete. Defense-in-depth — normal path deletes pods immediately after job completion.

### add-pss-restricted-defaults

Mutates incoming Pods to add security context fields required for Pod Security Standards (PSS) Restricted profile compliance. Only sets fields that are not already defined, preserving app-specific configurations. Adds `seccompProfile: RuntimeDefault`, `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, and drops all capabilities on containers and init containers.

**Excluded Namespaces:** kube-system, kube-public, kube-node-lease, flux-system, kyverno, rook-ceph, falco-system, irq-balance, spegel, velero, observability, nut-system, dev-debug

### add-default-topology-spread

Automatically injects topology spread constraints on Deployments and StatefulSets that don't already have them. Uses soft constraints (`ScheduleAnyway`) with `maxSkew: 1` to ensure balanced pod distribution across nodes without blocking scheduling. Matches on `app.kubernetes.io/name` label for the label selector.

**Excluded Namespaces:** kube-system, kube-public, kube-node-lease, flux-system, kyverno

### authentik-outpost-resources

Injects default resource requests and limits into Authentik outpost Deployments (matched by label `app.kubernetes.io/managed-by: goauthentik.io`) that don't already have resources set. Ensures outpost pods have Burstable QoS and VPA can generate recommendations.

**Resources Applied:**

| Resource | Request | Limit |
| -------- | ------- | ----- |
| CPU      | 5m      | --    |
| Memory   | 32Mi    | 64Mi  |

### Adding Namespace Exclusions

1. Edit `cluster/apps/kyverno/policies/app/default-limitrange.yaml`

2. Add namespace to the `exclude.any.resources.names` list

3. Commit and push

4. If policy update is rejected (immutable field error):

   ```bash
   kubectl delete clusterpolicy add-default-limitrange
   flux reconcile ks kyverno-policies --with-source
   ```

## Troubleshooting

### Common Issues

1. **Pod fails with "requests must be less than or equal to limit"**

   - **Cause**: App requests more memory than LimitRange default limit
   - **Resolution**: Either add explicit limits to the app, or exclude the namespace from the policy

2. **LimitRange not created in new namespace**

   - **Diagnosis**: Check if namespace is in exclude list or policy is ready

   - **Resolution**:

     ```bash
     kubectl get clusterpolicy add-default-limitrange -o jsonpath='{.status.conditions}'
     kubectl logs -n kyverno -l app.kubernetes.io/component=background-controller --tail=20
     ```

3. **Orphaned LimitRanges after policy changes**

   - **Cause**: Policy deleted without `synchronize: true`
   - **Resolution**: With `synchronize: true`, Kyverno auto-cleans generated resources

## References

- [Kyverno Generate Rules](https://kyverno.io/docs/writing-policies/generate/)
- [LimitRange Documentation](https://kubernetes.io/docs/concepts/policy/limit-range/)
