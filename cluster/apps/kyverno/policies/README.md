# kyverno-policies - Cluster Policies

## Overview

Cluster-wide Kyverno policies. Each policy's intent is in its manifest and `policies.kyverno.io/description` annotation; this README covers the behaviour that is easy to trip over. None of them apply in `kube-system` or `kyverno` (see [kyverno](../kyverno/README.md)).

## Policies

### add-helmrelease-defaults

Fills in `timeout`, `install`, `upgrade` and `rollback` on HelmReleases using `+(anchor)` syntax, so any field set in a HelmRelease wins. `interval` is not defaulted; every HelmRelease sets it explicitly. Because the whole `install` / `upgrade` / `rollback` block is anchored, setting **any** key in one of them (for example `upgrade.crds`) drops all the other defaults for that block - copy the full
block when overriding.

HelmReleases in `kube-system` are never mutated and fall back to helm-controller defaults (5m timeout), which is why `cilium` sets `timeout: 10m` itself.

### inject-claude-agent-config

Injects credentials, MCP config, settings profiles, plugin bootstrap and repo clone init containers into agent pods. Documented with the agent design in [claude-agents-shared](../../claude-agents-shared/README.md).

### set-agent-deadline

Paired with `validate-agent-deadline`. `set-agent-deadline` sets `activeDeadlineSeconds` on pods labelled `managed-by: n8n-claude-code` from their `agent-timeout` annotation, falling back to 3h when it is missing. `validate-agent-deadline` (Enforce) rejects any agent pod that still has no deadline, so a mutation failure blocks the pod rather than letting it run forever. Pods labelled
`app: claude-code-persistent` are excluded from both. Per-role timeouts are set by the worker; see [agent-queue-worker](../../agent-worker-system/agent-queue-worker/README.md#timeouts).

### cleanup-agent-pods

Hourly `ClusterCleanupPolicy` removing `Succeeded`/`Failed` agent pods that n8n did not delete. Needs the pod `delete` RBAC granted in the kyverno values.

### add-pss-restricted-defaults

Adds seccomp, `runAsNonRoot`, `allowPrivilegeEscalation: false` and `drop: [ALL]` to new pods where unset. Namespaces running legitimately privileged workloads are excluded in the manifest. A pod that needs root or capabilities in a non-excluded namespace must set those fields explicitly; the anchors leave explicit values alone. Other policies layer on top of this one - `qdrant-allow-init-root`
(in `qdrant-system`) and `restrict-privileged-to-coder-workspace-sa` (in `coder-workspaces`) live with their apps, not here.

### add-default-topology-spread

Adds a soft (`ScheduleAnyway`, `maxSkew: 1`) hostname spread keyed on `app.kubernetes.io/name` to Deployments and StatefulSets without one. Soft constraints never block scheduling, so balance is enforced after the fact by the [descheduler](../../kube-system/descheduler/README.md).

### authentik-outpost-resources

Authentik creates outpost Deployments with no resource requests, which leaves them BestEffort and invisible to VPA. This policy adds small defaults to Deployments labelled `app.kubernetes.io/managed-by: goauthentik.io`.

### remove-image-pull-secrets

Strips `imagePullSecrets` from pods pulling from GHCR or Docker Hub. Registry credentials for those registries are set at the node level in `talos/patches/all/07-configure-registries.yaml.tpl`, so per-pod pull secrets (often injected by charts) are redundant and break when the named secret does not exist in the pod's namespace.

## Troubleshooting

1. **Policy update rejected with an immutable-field error**
   - **Fix**: Delete the ClusterPolicy and let Flux recreate it.

## References

- [Kyverno mutate rules and anchors](https://kyverno.io/docs/writing-policies/mutate/)
