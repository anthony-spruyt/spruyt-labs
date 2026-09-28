# Flux Instance - GitOps Controllers

## Overview

`FluxInstance` rendered by flux-operator; it defines the Flux controllers and the root sync of `./cluster/flux/cluster`. Flux manages itself from here after bootstrap.

## Prerequisites

Two secrets in `flux-system` are created by hand at bootstrap and are not in Git:

| Secret            | Contents                                  | Used by                                |
| ----------------- | ----------------------------------------- | -------------------------------------- |
| `flux-gitops-key` | `identity` (deploy key) and `known_hosts` | `sync.pullSecret` - Git clone over SSH |
| `sops-age`        | `age.agekey` - the SOPS Age private key   | Decryption for every Kustomization     |

`talos/legacy/install-c1.sh` shows the commands used to create them.

## Operations

### Bootstrap

`talos/helmfile/flux.yaml` installs flux-operator and flux-instance with the same `values.yaml` files as these HelmReleases, so a fresh cluster comes up with identical settings. The chart versions pinned there are **not** tracked by Renovate and lag the OCIRepository tags in `cluster/flux/meta/repositories/oci/`; Flux upgrades itself on first reconcile, so the lag is harmless but the bootstrap
version should stay recent enough to understand the current CRDs.

### Patches worth knowing

- **Namespace label**: flux-operator owns the `flux-system` Namespace and overwrites labels from `namespace.yaml`, so `descheduler.kubernetes.io/exclude` is added through a kustomize patch here instead.
- **Controller tuning**: concurrency, in-memory kustomize builds, Helm OOM watch and anti-affinity are all patches in `app/values.yaml`. helm-controller concurrency is deliberately lower than the others to cap CPU spikes (#233).

### Cross-namespace access to `sops-age`

`app/sops-age-reader-rbac.yaml` lets the `sops-age-reader` ServiceAccount in `coder-workspaces` read the Age key, so ESO can sync it into spruyt-labs Coder workspaces. Anything holding that SA can decrypt every secret in the repo; do not widen the binding.
