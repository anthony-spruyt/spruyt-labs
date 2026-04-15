# coder-template-sync — GitOps template sync for Coder

## Overview

Hash-triggered Job pushes every directory under `app/templates/**` to the Coder
control plane via the `gitops-bot` headless user. A CronJob
(every 3 days, `0 2 */3 * *`) rotates the `gitops-bot` session token and patches the Secret
in place; the SOPS-seeded manifest uses
`kustomize.toolkit.fluxcd.io/ssa: IfNotPresent` so runtime rotations are
preserved.

Image: `ghcr.io/anthony-spruyt/coder-gitops` (see
[container-images#458](https://github.com/anthony-spruyt/container-images/issues/458)).

> **Note**: This component has no HelmRelease — it ships Kustomize-rendered
> resources directly.

## Prerequisites

- `coder` Kustomization deployed (dependsOn).
- `gitops-bot` headless user exists in Coder with `template-admin` site role.
- `coder-gitops-bot-token` Secret seeded by Flux from
  `app/secret-bootstrap.sops.yaml` (keys: `token`, `token-id`).

## Operation

### Add a new template

1. Create `app/templates/<name>/` and place Terraform sources inside.
2. Append each file to `configMapGenerator.files` in
   `app/kustomization.yaml` (explicit list, not a glob, so the hash changes
   visibly).
3. Commit + push — Flux re-renders the ConfigMap with a new hash, which
   triggers a new `coder-template-push` Job.

### Manual push (escape hatch)

From a shell with `coder` CLI logged in as an admin:

```bash
coder templates push <name> -y
```

### Manual rotation

```bash
kubectl -n coder-system create job \
  --from=cronjob/coder-token-rotation rotation-smoke-test
kubectl -n coder-system logs job/rotation-smoke-test
```

### Reconcile

```bash
flux reconcile kustomization coder-template-sync --with-source
kubectl -n coder-system get jobs,cronjobs \
  -l app.kubernetes.io/name=coder-template-sync
```

## Troubleshooting

1. **Rotation CronJob fails, token expires**
   - **Symptom**: Job complains `401 unauthorized`.
   - **Resolution**: Delete the Secret so Flux re-seeds from SOPS, then
     trigger the CronJob manually:
     `kubectl -n coder-system delete secret coder-gitops-bot-token && flux reconcile kustomization coder-template-sync`.

2. **Template ConfigMap exceeds 1 MiB**
   - **Symptom**: Flux reports `ConfigMap ... is invalid` / `Request entity too large`.
   - **Resolution**: Switch strategy to a Flux `GitRepository` source mounted
     via `volumes.persistentVolumeClaim` or an init container that clones at
     runtime. Current size budget: ~900 kB.

3. **Job fails with `cannot connect to coder`**
   - **Symptom**: `push-templates.sh` logs `dial tcp: lookup coder...`.
   - **Resolution**: Verify the CiliumNetworkPolicy
     `coder-template-sync-egress` selector still matches the Coder pod
     (`app.kubernetes.io/name: coder`) and the Service port is `80`.

## References

- [Coder templates](https://coder.com/docs/admin/templates)
- [Coder long-lived tokens](https://coder.com/docs/admin/users/sessions-tokens)
- [Flux Kustomization `force`](https://fluxcd.io/flux/components/kustomize/kustomizations/#force)
- [Flux SSA strategies](https://fluxcd.io/flux/components/kustomize/kustomizations/#controlling-the-apply-behavior-of-resources)
