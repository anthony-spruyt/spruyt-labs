# Flux GitOps Runbook

## Purpose and Scope

This runbook governs the FluxCD control plane housed under `cluster/flux/`.
It defines how platform operators bootstrap Flux onto a Talos-backed cluster,
maintain reconciliation health, curate Git/OCI/Helm sources, and recover from
controller or automation failures. The guidance aligns with the
repository-wide runbook standards declared in the root documentation and
complements the workload-focused procedures in `cluster/apps/`.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                          | Description                                                                                                                                    |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `cluster/flux/cluster/ks.yaml`                | Aggregate Flux `Kustomization` definitions that reconcile meta configuration first and then hand off to the broader `cluster/apps/` hierarchy. |
| `cluster/flux/meta/`                          | Flux `Kustomization` that materializes cluster-scoped settings (ConfigMaps, SOPS secrets) and delegates to the repository catalog.             |
| `cluster/flux/meta/cluster-settings.yaml`     | Non-secret key-value pairs exposed to downstream Kustomizations through `postBuild.substituteFrom`.                                            |
| `cluster/flux/meta/cluster-secrets.sops.yaml` | Encrypted values decrypted by Flux using the `sops-age` secret referenced in `cluster/flux/cluster/ks.yaml`.                                   |
| `cluster/flux/meta/repositories/`             | Canonical registry of Flux `GitRepository`, `OCIRepository`, and `HelmRepository` sources. Subdirectories partition sources by type.           |
| `cluster/flux/meta/repositories/helm/`        | Helm repositories consumed by `HelmRelease` objects throughout `cluster/apps/`. Each file pins repository endpoints and intervals.             |
| `cluster/flux/meta/repositories/oci/`         | OCI-backed sources for GitOps artifacts (e.g., Flux operator bundles, pre-rendered charts).                                                    |
| `.taskfiles/flux/tasks.yaml`                  | Task runner entry point for launching Flux Capacitor to visualize reconciliation state (CLI name `task flux:cap`).                             |

<!-- markdownlint-enable MD013 -->

## Operational Runbook

### Summary

Bootstrap and operate the Flux GitOps control plane, ensuring declarative
resources under `cluster/` reconcile predictably, sources remain healthy,
automation jobs execute safely, and failures are remediated with minimal
downtime.

### Preconditions

- Execute from the repository devcontainer or install `flux`, `kubectl`,
  `age`, `sops`, and `task` locally.
- Possess access to the Age identity file that decrypts
  `cluster/flux/meta/cluster-secrets.sops.yaml` and the `talosconfig` used by
  bootstrap Talos nodes.
- Confirm network reachability from the management workstation to the Talos
  control plane API and to upstream Git/OCI/Helm endpoints.
- Verify no outstanding Flux suspensions that would block bootstrap or
  reconciliation (`flux get kustomizations -n flux-system`).

### Procedure

#### Phase 1 – Bootstrap or Rebuild Flux

1. Ensure the target cluster is reachable and Kubernetes credentials are
   exported (`export KUBECONFIG=...`).
2. Install Flux CLI parity via the devcontainer or `task dev-env:install-flux`.
3. Create the `flux-system` namespace and bootstrap manifests with Flux CLI:

   ```bash
   flux bootstrap git \
     --components-extra=image-reflector-controller,image-automation-controller \
     --url=ssh://git@github.com/spruyt-labs/spruyt-labs.git \
     --branch=main \
     --path=cluster \
     --token-auth
   ```

4. Import the Age key material so Flux can decrypt SOPS secrets:

   ```bash
   kubectl -n flux-system create secret generic sops-age \
     --from-file=age.agekey=${HOME}/.config/sops/age/keys.txt \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

5. Apply repository metadata if bootstrap used a minimal path:

   ```bash
   kubectl apply -f cluster/flux/meta/cluster-settings.yaml
   kubectl apply -k cluster/flux/meta
   ```

6. Kick off an initial reconciliation to cascade into workloads:

   ```bash
   flux reconcile kustomization cluster-meta --with-source
   flux reconcile kustomization cluster-apps --with-source
   ```

#### Phase 2 – Ongoing Sync and Reconciliation Management

1. Inspect controller health:

   ```bash
   flux check
   flux get kustomizations -n flux-system
   flux get helmreleases -A
   ```

2. Force reconciliation after merges or hotfixes:

   ```bash
   flux reconcile kustomization <kustomization-name> --with-source
   flux reconcile helmrelease <release-name> -n <namespace> --with-source
   ```

3. Review detailed status and events:

   ```bash
   flux logs --kind Kustomization --name <name> -n flux-system
   flux events
   ```

4. For visual diffs, launch Flux Capacitor (`task flux:cap`) and authenticate
   via the forwarded GUI session.

#### Phase 3 – Source Management (Git, OCI, Helm)

1. Add or update sources inside `cluster/flux/meta/repositories/` and commit
   the changes.
2. Validate source connectivity:

   ```bash
   flux get sources git,helm,oci -A
   flux reconcile source git flux-system --with-source
   flux reconcile source helm <repo-name> -n flux-system
   ```

3. Rotate authentication secrets (SSH deploy keys, registry credentials) by
   updating the relevant SOPS-encrypted entries and reapplying
   `cluster/flux/meta`:

   ```bash
   sops cluster/flux/meta/cluster-secrets.sops.yaml
   kubectl apply -k cluster/flux/meta
   ```

#### Phase 4 – Automation Jobs and Image Updates

1. When image automation controllers are enabled, verify policies:

   ```bash
   flux get image repositories -A
   flux get image policies -A
   flux get image updateautomations -A
   ```

2. Trigger an image automation run or dry-run diff:

   ```bash
   flux reconcile image repository <name> -n flux-system
   flux image update --dry-run
   ```

3. Commit Flux-generated automation changes promptly to avoid drift. Review
   diffs with `flux diff ks <name> --path ./cluster/...` before approval.

#### Phase 5 – Rollback and Recovery

1. Revert problematic commits and push to `main` to restore prior desired
   state.
2. Temporarily suspend Flux objects when isolation is required:

   ```bash
   flux suspend kustomization <name> -n flux-system
   flux suspend helmrelease <release> -n <namespace>
   ```

   Resume once remediation is complete:

   ```bash
   flux resume kustomization <name> -n flux-system
   ```

3. Recreate Flux components if the namespace becomes unhealthy:

   ```bash
   kubectl delete namespace flux-system --wait=false
   flux bootstrap git \
     --url=ssh://git@github.com/spruyt-labs/spruyt-labs.git \
     --branch=main \
     --path=cluster
   ```

4. Validate Talos control plane health (`talosctl health`) before concluding
   recovery.

### Validation

- Confirm `flux get kustomizations -n flux-system` reports `Ready=True` for
  `cluster-meta` and `cluster-apps`.
- Ensure `kubectl get pods -n flux-system` shows every controller in `Ready`
  state.
- Check `flux reconcile kustomization cluster-apps --with-source` completes
  without errors after significant changes.

### Troubleshooting Guidance

Refer to the dedicated troubleshooting section below for detailed diagnostics
on reconciliation stalls, failed Kustomizations, source authentication errors,
and automation issues.

### Escalation

- Engage the platform on-call channel with recent `flux logs`, commit hashes,
  and runbook references.
- Coordinate with secrets owners before rotating credentials impacting shared
  repositories.
- Escalate to Talos owners if bootstrap failures trace back to control-plane
  instability.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Tooling                                                   | Purpose                                                                                                   |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `task dev-env:lint`                                       | Executes super-linter (markdownlint, yamllint, prettier, gitleaks) for repository parity prior to merges. |
| `task pre-commit:run`                                     | Runs local hooks mirroring CI enforcement before pushing changes.                                         |
| `flux diff ks <name> --path=./cluster/...`                | Previews reconciled changes for a given `Kustomization` to surface destructive diffs.                     |
| `flux diff hr <release> --namespace <ns>`                 | Evaluates Helm release deltas before applying.                                                            |
| GitHub Actions `lint.yaml` & `flux-differ.yaml`           | CI signal covering linting, schema validation, and Flux drift detection.                                  |
| `flux reconcile kustomization cluster-meta --with-source` | Verifies meta layer integrity after repository updates.                                                   |
| `kubectl get kustomizations,helmreleases -A`              | Manual spot-check of reconciliation status across namespaces.                                             |

<!-- markdownlint-enable MD013 -->

## Troubleshooting

### Stuck Reconciliations

1. Inspect reconciliation summary:

   ```bash
   flux get kustomizations -n flux-system
   flux events --for Kustomization/<name> -n flux-system
   ```

2. Detect apply conflicts or drift using Flux Capacitor or `flux diff ks`.
3. Clear stuck locks by reapplying:

   ```bash
   flux suspend kustomization <name> -n flux-system
   flux resume kustomization <name> -n flux-system
   ```

### Failed Kustomizations or Helm Releases

1. Retrieve detailed status:

   ```bash
   flux logs --kind Kustomization --name <name> -n flux-system
   flux get helmrelease <release> -n <namespace> -o yaml
   ```

2. Validate rendered manifests locally (`kustomize build`, `helm template`,
   `kubeconform`).
3. Ensure dependencies (CRDs, namespaces, secrets) exist prior to
   reconciliation.

### Source Authentication Issues

1. Check source readiness:

   ```bash
   flux get sources git -A
   flux get sources helm -A
   flux get sources oci -A
   ```

2. Confirm credentials stored in
   `cluster/flux/meta/cluster-secrets.sops.yaml` decrypt correctly by running
   `sops -d`.
3. Rotate deploy keys or tokens, re-encrypt with Age, and reapply
   `cluster/flux/meta`.

### Image Automation Failures

1. Review automation objects:

   ```bash
   flux get image updateautomations -A
   flux logs --kind ImageUpdateAutomation --name <name> -n <namespace>
   ```

2. Ensure policies resolve tags (`flux get image policies -A`). Update SemVer
   filters if no tags match.
3. Validate commit permissions for automation bots and reconcile the Git
   source after adjustments.

## References and Cross-links

- Runbook standards overview: [`README.md`](../../README.md#runbook-standards)
- Application deployment guide: [`cluster/apps/README.md`](../apps/README.md)
- Custom resource lifecycle guidance: [`cluster/crds/README.md`](../crds/README.md)
- Talos bootstrap and control-plane recovery: [`talos/README.md`](../../talos/README.md)
- Secrets management workflows: [`.taskfiles/sops/tasks.yaml`](../../.taskfiles/sops/tasks.yaml)
- Flux visualization task: [`.taskfiles/flux/tasks.yaml`](../../.taskfiles/flux/tasks.yaml)

## Changelog

- _TBD — record future updates using the format_
  _`yyyy-mm-dd · short summary · PR/commit reference`._
