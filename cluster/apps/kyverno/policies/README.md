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

`ghcr.io/berriai/litellm*` images in `litellm` pods must carry a cosign signature that verifies against upstream BerriAI's public key (Deny mode). The key is inline in the manifest and also committed in litellm-middleware as `cosign/litellm.pub`, where CI verifies the pinned image against it.

The admission controller looks up signatures on `ghcr.io` and `pkg-containers.githubusercontent.com` and fetches Sigstore TUF metadata from `tuf-repo-cdn.sigstore.dev`; `allow-image-verification-egress` in [network-policies.yaml](../kyverno/app/network-policies.yaml) allows exactly those hosts. The `LiteLLMImageSignatureRejected` and `LiteLLMImageCheckUnavailable` alerts
(`verify-litellm-image-vmrule.yaml`) are critical and route through Alertmanager.

## Operations

### Restoring LiteLLM admission

When LiteLLM pods cannot be admitted and a revert of the policy commit cannot land in time:

1. Stop Flux from recreating the policy: `flux suspend kustomization kyverno-policies -n flux-system`
2. Remove the policy: `kubectl delete imagevalidatingpolicy verify-litellm-image`
3. Restart LiteLLM and check the pods: `kubectl rollout restart deployment/litellm -n litellm`, then `kubectl get pods -n litellm`. Repeated denials make the ReplicaSet back off, so it does not retry promptly on its own.
4. Land the fix on `main`, then `flux resume kustomization kyverno-policies -n flux-system`. Flux recreates the policy from `main`.

### Rotating the LiteLLM cosign key

The key lives in two places: `spec.attestors[].cosign.key.data` in `verify-litellm-image.yaml`, and `cosign/litellm.pub` in litellm-middleware. `attestors` is a CEL map: name attestors without hyphens so `attestors.<name>` parses, and never leave an expression naming a removed attestor: it still compiles, but the lookup errors at admission and denies the pod unless another `||` call passes. Change
both keys in this order so the pinned image always verifies:

1. Add the new key to `verify-litellm-image.yaml` as a second attestor named `cosignNext` and replace the validation expression with one call per attestor, joined with `||`, current key first. One call per attestor because a single call with both attestors caches a success only when every attestor verifies. Wait for Flux to reconcile `kyverno-policies`.

   ```text
   images.containers.map(image, verifyImageSignatures(image, [attestors.cosign]) > 0 || verifyImageSignatures(image, [attestors.cosignNext]) > 0).all(e, e)
   ```

2. Once step 1 has reconciled:

   1. Merge the litellm-middleware PR (the pin and `cosign/litellm.pub` in one PR).
   2. Merge the spruyt-labs Renovate bump.
   3. Confirm the pods run the new digest.

3. In one commit, remove the old attestor and its call in the expression, and rename `cosignNext` to `cosign` in the attestor and the expression, so the next rotation starts from the same names.

When upstream revokes a key instead of rotating it, do not overlap the keys: once the litellm-middleware PR has merged and the spruyt-labs Renovate bump PR is open, replace the key data of the `cosign` attestor in one commit and leave the expression as it is. New LiteLLM pods are denied until the bump lands, so merge it straight after.

## Troubleshooting

1. **Policy update rejected with an immutable-field error**
   - **Fix**: Delete the ClusterPolicy and let Flux recreate it.
2. **LiteLLM pods denied although the pinned image is signed**
   - **Cause**: A lookup failed, usually egress from the admission controller to `ghcr.io`, `pkg-containers.githubusercontent.com` or `tuf-repo-cdn.sigstore.dev`. A failed signature or Sigstore (TUF) fetch counts as zero verified keys and fires `LiteLLMImageSignatureRejected`. Of the lookups, only a failed image manifest or config fetch, or a webhook timeout, fires `LiteLLMImageCheckUnavailable`.
     The admission controller logs show which.
   - **Fix**: Repair `allow-image-verification-egress` and let Flux reconcile. If service cannot wait, follow [Restoring LiteLLM admission](#restoring-litellm-admission).

## References

- [Kyverno mutate rules and anchors](https://kyverno.io/docs/writing-policies/mutate/)
- [Kyverno ImageValidatingPolicy](https://kyverno.io/docs/policy-types/image-validating-policy/)
