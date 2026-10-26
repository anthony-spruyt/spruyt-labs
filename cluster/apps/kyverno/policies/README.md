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
`app: claude-code-persistent` are excluded from both. n8n's Claude Code node writes the `agent-timeout` annotation from the `timeout_seconds` its caller sends.

### cleanup-agent-pods

Hourly `ClusterCleanupPolicy` removing `Succeeded`/`Failed` agent pods that n8n did not delete. Needs the pod `delete` RBAC granted in the kyverno values.

### add-pss-restricted-defaults

Adds seccomp, `runAsNonRoot`, `allowPrivilegeEscalation: false` and `drop: [ALL]` to new pods where unset. Namespaces running legitimately privileged workloads are excluded in the manifest. A pod that needs root or capabilities in a non-excluded namespace must set those fields explicitly; the anchors leave explicit values alone. Other policies layer on top of this one;
`restrict-privileged-to-coder-workspace-sa` (in `coder-workspaces`) lives with its app, not here.

### add-default-topology-spread

Adds a soft (`ScheduleAnyway`, `maxSkew: 1`) hostname spread keyed on `app.kubernetes.io/name` to Deployments and StatefulSets without one. Soft constraints never block scheduling, so balance is enforced after the fact by the [descheduler](../../kube-system/descheduler/README.md).

### authentik-outpost-resources

Authentik creates outpost Deployments with no resource requests, which leaves them BestEffort and invisible to VPA. This policy adds small defaults to Deployments labelled `app.kubernetes.io/managed-by: goauthentik.io`.

### remove-image-pull-secrets

Strips `imagePullSecrets` from pods pulling from GHCR or Docker Hub. Registry credentials for those registries are set at the node level in `talos/patches/all/07-configure-registries.yaml.tpl`, so per-pod pull secrets (often injected by charts) are redundant and break when the named secret does not exist in the pod's namespace.

### verify-litellm-image

`ImageValidatingPolicy` in Deny mode. Pods in `litellm` may only run `ghcr.io/berriai/litellm*` images whose cosign signature verifies against upstream BerriAI's public key. It runs at pod admission (CREATE and UPDATE) on its own webhook, scoped to the `litellm` namespace. The key sits inline in the manifest and is also committed in litellm-middleware as `cosign/litellm.pub`, where CI verifies the pinned image against it.

The admission controller looks up signatures on `ghcr.io` and `pkg-containers.githubusercontent.com` and fetches Sigstore TUF metadata from `tuf-repo-cdn.sigstore.dev`; `allow-image-verification-egress` in [kyverno](../kyverno/README.md) allows exactly those hosts. The `LiteLLMImageSignatureRejected` and `LiteLLMImageCheckUnavailable` alerts (`verify-litellm-image-vmrule.yaml`) are critical and route through Alertmanager.

## Operations

### Restoring LiteLLM admission

When LiteLLM pods cannot be admitted and a revert of the policy commit cannot land in time:

1. Stop Flux from recreating the policy: `flux suspend kustomization kyverno-policies -n flux-system`
2. Remove the policy: `kubectl delete imagevalidatingpolicy verify-litellm-image`
3. Land the fix on `main`, then `flux resume kustomization kyverno-policies -n flux-system`. Flux recreates the policy from `main`.

### Rotating the LiteLLM cosign key

The key lives in two places: `spec.attestors[].cosign.key.data` in `verify-litellm-image.yaml`, and `cosign/litellm.pub` in litellm-middleware. Change them in this order so the pinned image always verifies:

1. Add the new key as a second attestor in `verify-litellm-image.yaml` and list it next to `attestors.cosign` in the validation expression. An image signed with either key passes.
2. Merge the LiteLLM bump to an image signed with the new key. litellm-middleware replaces `cosign/litellm.pub` in the same PR as the pin it verifies.
3. Drop the old key: remove the old attestor from `verify-litellm-image.yaml`.

## Troubleshooting

1. **Policy update rejected with an immutable-field error**
   - **Fix**: Delete the ClusterPolicy and let Flux recreate it.
2. **LiteLLM pods denied although the pinned image is signed**
   - **Cause**: The signature or Sigstore lookup failed, usually egress from the admission controller to `ghcr.io`, `pkg-containers.githubusercontent.com` or `tuf-repo-cdn.sigstore.dev`. The admission controller logs and the `LiteLLMImageCheckUnavailable` alert show which.
   - **Fix**: Repair `allow-image-verification-egress` and let Flux reconcile. If service cannot wait, follow [Restoring LiteLLM admission](#restoring-litellm-admission).

## References

- [Kyverno mutate rules and anchors](https://kyverno.io/docs/writing-policies/mutate/)
- [Kyverno ImageValidatingPolicy](https://kyverno.io/docs/policy-types/image-validating-policy/)
