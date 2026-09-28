# Flux Instance - GitOps Controllers

## Overview

`FluxInstance` rendered by flux-operator; it defines the Flux controllers and the root sync of `./cluster/flux/cluster`. Flux manages itself from here after bootstrap.

## Prerequisites

Two secrets in `flux-system` are created by hand at bootstrap and are not in Git:

| Secret            | Contents                                  | Used by                                |
| ----------------- | ----------------------------------------- | -------------------------------------- |
| `flux-gitops-key` | `identity` (deploy key) and `known_hosts` | `sync.pullSecret` - Git clone over SSH |
| `sops-age`        | `age.agekey` - the SOPS Age private key   | Decryption for every Kustomization     |

[docs/bootstrap.md section 4](../../../../docs/bootstrap.md#4-flux) has the commands that create them.

## Operations

### Bootstrap

`talos/helmfile/flux.yaml.gotmpl` installs flux-operator and flux-instance with the same `values.yaml` files as these HelmReleases, and reads the chart URL and tag from the OCIRepositories in `cluster/flux/meta/repositories/oci/`, so a fresh cluster comes up with the same versions and settings that Renovate keeps current.

### Rotate the deploy key

The private key lives only on the host (`~/.secrets/flux-gitops-key`, `.pub` beside it) and in the `flux-gitops-key` Secret. Its public half is the repository deploy key whose title starts with `flux-gitops`. Flux only reads, so the key must not have write access. Add keys in the GitHub UI, not with `gh repo deploy-key add`: keys added by `gh` are deleted when its token is revoked.

1. On the host, generate the new pair next to the old one:

   ```bash
   ssh-keygen -t ed25519 -N "" -C flux-gitops -f ~/.secrets/flux-gitops-key.new
   ```

2. GitHub → repository Settings → Deploy keys → Add deploy key. Title `flux-gitops-<yyyy-mm>`, paste `flux-gitops-key.new.pub`, leave **Allow write access** unticked.

3. Copy `flux-gitops-key.new` into the devcontainer and replace the Secret:

   ```bash
   ssh-keyscan github.com > /tmp/known_hosts
   kubectl -n flux-system create secret generic flux-gitops-key \
     --from-file=identity=<path-to-flux-gitops-key.new> \
     --from-file=known_hosts=/tmp/known_hosts \
     --dry-run=client -o yaml | kubectl apply -f -
   flux reconcile source git flux-system -n flux-system
   ```

   **Good:** `Ready True` and a fresh `stored artifact` revision in `flux get sources git flux-system -n flux-system`.

4. Delete the old deploy key in GitHub, and on the host replace `flux-gitops-key` / `.pub` with the `.new` files. Delete the copy inside the devcontainer.

### Patches worth knowing

- **Namespace label**: flux-operator owns the `flux-system` Namespace and overwrites labels from `namespace.yaml`, so `descheduler.kubernetes.io/exclude` is added through a kustomize patch here instead.
- **Controller tuning**: concurrency, in-memory kustomize builds, Helm OOM watch and anti-affinity are all patches in `app/values.yaml`. helm-controller concurrency is deliberately lower than the others to cap CPU spikes (#233).

### Cross-namespace access to `sops-age`

`app/sops-age-reader-rbac.yaml` lets the `sops-age-reader` ServiceAccount in `coder-workspaces` read the Age key, so ESO can sync it into spruyt-labs Coder workspaces. Anything holding that SA can decrypt every secret in the repo; do not widen the binding.
