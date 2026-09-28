# Flux

## Overview

Root of the GitOps tree. Flux itself is installed and upgraded by the Flux Operator from [`flux-instance`](../apps/flux-system/flux-instance/README.md), not by `flux bootstrap`. Installing it on a new cluster is step 4 of [docs/bootstrap.md](../../docs/bootstrap.md#4-flux).

Pushes to `main` reconcile within seconds through a GitHub webhook ([flux-receivers](../apps/flux-system/flux-receivers/README.md)); the root intervals are only a fallback.

## Reconciliation chain

```text
FluxInstance "flux" (cluster/apps/flux-system/flux-instance)
  -> Kustomization flux-system  path ./cluster/flux/cluster
       -> Kustomization cluster-meta  path ./cluster/flux/meta
            settings, secrets, priority classes, cluster-wide network policies, sources
       -> Kustomization cluster-apps  path ./cluster/apps  (dependsOn cluster-meta)
            every cluster/apps/<ns>/<app>/ks.yaml
```

Chart and Git sources for all apps live in [`meta/repositories/`](meta/repositories/README.md), so an app's `ks.yaml` cannot reconcile until `cluster-meta` is ready.

## Defaults injected into child objects

`cluster/ks.yaml` patches every object of a kind below it, so the app manifests leave these fields out. Set the matching label to `"true"` on an object to opt out.

| Applied to                          | Default                                                                 | Opt-out label                                    |
| ----------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------ |
| Kustomizations under `cluster-apps` | `interval` and `sourceRef` (the `flux-system` GitRepository)            | `kustomizationdefaults.flux.home.arpa/disabled`  |
| Kustomizations under `cluster-apps` | SOPS decryption with the `sops-age` secret                              | `sops.flux.home.arpa/disabled`                   |
| Kustomizations under `cluster-apps` | `postBuild.substituteFrom` the `cluster-settings` and `cluster-secrets` | `substitution.flux.home.arpa/disabled`           |
| HelmRepositories in `cluster-meta`  | `interval`, `timeout`                                                   | `helmrepositorydefaults.flux.home.arpa/disabled` |
| OCIRepositories in `cluster-meta`   | `interval`, `timeout`, Helm chart `layerSelector`                       | `ocirepositorydefaults.flux.home.arpa/disabled`  |

Opt out when the defaults are wrong for the object: the upstream CRD Kustomizations (for example `cilium/ks.yaml`) pull from their own GitRepository and must not substitute or decrypt upstream YAML, and `coder-template-sync` ships HCL whose `${...}` cannot be escaped.

## Variable substitution

Every Kustomization under `cluster-apps` substitutes `${VAR}` from `meta/cluster-settings.yaml` (plain) and `meta/cluster-secrets.sops.yaml` (encrypted). Use these instead of hardcoding domains or addresses, for example `${EXTERNAL_DOMAIN}`.

- List the available names (keys only, no values) with `task flux:list-vars`.
- A literal `${...}` that Flux must leave alone, such as a shell or JavaScript template, is written `$${...}`.
- Add or change a secret value by editing the file with `sops cluster/flux/meta/cluster-secrets.sops.yaml` and committing it. Flux decrypts it in the cluster; do not decrypt it on the command line.

## Tooling

- `task flux:cap` starts [Flux Capacitor](https://github.com/gimlet-io/capacitor), a local web UI for Kustomization and HelmRelease state.
