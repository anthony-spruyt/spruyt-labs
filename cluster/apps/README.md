# Cluster Applications Runbook

## Purpose and Scope

This runbook governs the authoring, deployment, and lifecycle management of
workloads committed under `cluster/apps/`. It aligns with the repository-wide
runbook standards defined in the root documentation and focuses on the operator
workflows necessary to introduce, update, validate, and roll back
namespace-scoped applications managed by FluxCD.

## Directory Layout

The directories under `cluster/apps/` follow a consistent structure so that Flux
Kustomizations and HelmReleases can be composed predictably.

<!-- markdownlint-disable MD013 -->

| Path                                                      | Purpose                                                                                                               |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `cluster/apps/<namespace>/kustomization.yaml`             | Namespace-level Kustomization that wires Flux into one or more application overlays.                                  |
| `cluster/apps/<namespace>/namespace.yaml`                 | Optional namespace manifest when the namespace is not provisioned elsewhere.                                          |
| `cluster/apps/<namespace>/<app>/ks.yaml`                  | Flux `Kustomization` declaring target namespace, interval, and the relative path to the application overlay (`app/`). |
| `cluster/apps/<namespace>/<app>/app/kustomization.yaml`   | Overlay assembling rendered resources (HelmRelease, ConfigMaps, PVCs, etc.) for the app.                              |
| `cluster/apps/<namespace>/<app>/app/release.yaml`         | Flux `HelmRelease` defining chart source, version, reconciliation cadence, and chart values.                          |
| `cluster/apps/<namespace>/<app>/app/values.yaml`          | Values supplied to the chart, typically with schema annotations for IDE validation.                                   |
| `cluster/apps/<namespace>/<app>/app/kustomizeconfig.yaml` | Optional Kustomize configuration for patch transformers (commonly for Helm managed resources).                        |
| `cluster/apps/<namespace>/<app>/app/*.yaml`               | Supporting manifests (PVCs, secret references, certificates) that must ship with the release.                         |
| `cluster/apps/<namespace>/<app>/resources/`               | Supplemental resources reconciled alongside the HelmRelease (RBAC, CRDs, etc.).                                       |

<!-- markdownlint-enable MD013 -->

## Operational Runbook

### Summary

Manage application overlays through GitOps. Author changes in feature branches,
validate with automated tooling, and rely on Flux to reconcile the committed
state into the cluster.

### Preconditions

- Work from the repository devcontainer or ensure the toolchain (`flux`,
  `kubectl`, `helm`, `sops`, `talhelper`, `kubeconform`) matches workspace
  expectations.
- Authenticate to required registries and decrypt SOPS-managed secrets with
  `sops --config .sops.yaml -d` or `task sops:decrypt` when editing secret
  overlays. Re-encrypt before committing.
- Maintain branch hygiene: one logical change per branch, descriptive commit
  messages referencing runbook updates, and an up-to-date `main`.
- Install and hydrate pre-commit hooks with `task pre-commit:init` to guarantee
  local lint parity with CI.
- Confirm that required secrets (SOPS files, external secret providers, Helm
  repository credentials) already exist or are part of the planned change set.

### Procedure

#### Plan and Review

1. Inspect existing overlays under the target namespace to understand
   dependencies (`ks.yaml`, `release.yaml`, ConfigMaps, PVCs).
2. Validate that chart repositories are defined in `cluster/flux/meta/repositories/`
   and add new repositories there when necessary.
3. Document intended changes in the app-specific README (if present) and decide
   whether additional runbooks or alerts are required.

#### Authoring

1. Start from a clean branch: `git checkout -b feat/<app>-<change>`.
2. Edit manifests or introduce new overlays following the directory conventions.
3. Validate manifest structure during authoring:
   - `task pre-commit:run` for repository-wide linting (YAML, markdown,
     gitleaks, terraform as applicable).
   - `kubeconform --summary cluster/apps/<namespace>/<app>/app` to ensure
     Kubernetes schema compliance.
   - `helm template --namespace <namespace> --values \
cluster/apps/<namespace>/<app>/app/values.yaml --debug <chart>` for chart
     rendering checks.

##### HelmRelease Authoring Example

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta2
kind: HelmRelease
metadata:
  name: example-app
  namespace: example
spec:
  interval: 30m
  chart:
    spec:
      chart: app-template
      version: 1.2.3
      sourceRef:
        kind: HelmRepository
        name: bjw-s-charts
        namespace: flux-system
  values:
    image:
      repository: ghcr.io/spruyt/example-app
      tag: 1.0.0
    ingress:
      enabled: true
      hosts:
        - host: example.internal
          paths:
            - path: /
              pathType: Prefix
```

##### Commit and Review Hygiene

1. Run `task dev-env:lint` to exercise the super-linter pipeline before opening
   a PR.
2. Commit with meaningful context, including runbook updates when applicable.
3. Open a pull request summarizing lifecycle phases touched (Plan, Apply,
   Validate) and link modified app runbooks.

#### Deployment

1. After merge, Flux reconciles automatically. To accelerate rollout or inspect
   diffs, run:
   - `flux diff ks cluster-apps --path=./cluster/apps/<namespace>/<app>` for a
     dry-run comparison.
   - `flux reconcile kustomization <app>-ks --with-source` to trigger
     reconciliation.
2. Observe reconciliation with `flux get kustomizations --namespace flux-system`
   and `flux get helmreleases -n <namespace>`.
3. For broader visibility, launch Flux Capacitor with `task flux:cap`.
4. When chart upgrades modify CRDs or cluster-scoped resources, land supporting
   manifests in `resources/` and reconcile them before the HelmRelease.

#### Post-deployment Validation

- Run `kubectl get pods -n <namespace>` and `kubectl describe` the workload to
  confirm readiness and health.
- Inspect `flux get helmrelease <app> -n <namespace>` for reconciliation status,
  revisions, and last apply errors.
- Execute application-specific smoke tests (HTTP checks, StatefulSet PVC
  binding, service endpoints) documented in the app README.
- Review `kubectl logs deployment/<app>` (or relevant controller) for regressions
  immediately after rollout.

#### Rollback and Undeploy

1. For configuration regressions, revert the offending commit (`git revert
<sha>`) and push the fix branch so Flux reapplies the prior desired state.
2. For urgent rollbacks without code changes, suspend the HelmRelease with
   `flux suspend helmrelease <app> -n <namespace>` and resume after remediation.
3. To remove an application, delete the directory and matching `ks.yaml` entries,
   commit the removal, and allow Flux to prune resources. Confirm PVCs and
   secrets are handled according to the change plan.

### Validation

- Capture validation results in the PR description (commands run, outputs,
  screenshots as needed).
- Update this README or the app-specific runbook with new validation probes
  introduced during the change.
- If validation deviates from the standard workflow, escalate via the path
  below.

### Troubleshooting

Common failure modes and diagnostics are captured in the
[Troubleshooting Playbooks](#troubleshooting-playbooks) section. Reference it
during incident handling and contribute new patterns after resolution.

### Escalation

- Notify the platform owner or on-call channel when a change impacts shared
  infrastructure (ingress, storage, DNS).
- Include links to PRs, Flux reconciliation logs, `kubectl` diagnostics, and
  runbook sections when escalating.
- Coordinate with secrets management owners before rotating credentials that
  affect multiple namespaces.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Tooling                                | Purpose                                                                                                           |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `task pre-commit:run`                  | Executes the local hook suite (yamllint, prettier, gitleaks, terraform fmt, SOPS checks).                         |
| `task dev-env:lint`                    | Runs the full super-linter pipeline used in CI to verify markdown, YAML, JSON, Terraform, and security baselines. |
| `kubeconform --summary`                | Validates rendered Kubernetes manifests against upstream schemas.                                                 |
| `helm template --debug` or `helm lint` | Ensures Helm charts render cleanly before Flux reconciliation.                                                    |
| `flux diff ks` / `flux diff hr`        | Previews Flux changes prior to merge for safer reviews.                                                           |
| Repository CI (`.github/workflows/*`)  | Confirms lint, formatting, and policy checks pass for app changes; monitor PR status checks for enforcement.      |

<!-- markdownlint-enable MD013 -->

## Troubleshooting Playbooks

<!-- markdownlint-disable MD013 -->

| Failure Mode                                      | Diagnostics                                                                         | Remediation                                                                                                           |
| ------------------------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Helm chart rendering errors during reconciliation | `flux logs --kind HelmRelease --name <app> -n <namespace>`, `helm template` locally | Correct values syntax, adjust chart versions, or align schema with upstream documentation.                            |
| Schema mismatches (kubeconform errors, CRD drift) | `kubeconform --summary`, `kubectl describe crd <resource>`                          | Update CRDs under `resources/`, rerun kubeconform, and ensure Flux applies CRD updates before HelmRelease changes.    |
| Flux reconciliation failures (`Ready=False`)      | `flux get kustomizations -n flux-system`, `flux events`                             | Resolve git authentication, SOPS decryption, or repository dependency issues, then trigger `flux reconcile`.          |
| Application unhealthy post-upgrade                | `kubectl get events -n <namespace>`, workload logs, service endpoints               | Revert the commit, suspend the HelmRelease, or rollback image tag/values. Validate dependent services before reapply. |
| Secret or config drift                            | `kubectl get secret <name> -n <namespace> -o yaml`, `task sops:decrypt`             | Regenerate secrets, re-encrypt with SOPS, commit updates, and ensure external secret stores are refreshed.            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Root runbook standards: [`README.md`](../../README.md#runbook-standards)
- Flux operations guide: [`cluster/flux/README.md`](../flux/README.md)
- Task automation index: [`Taskfile.yml`](../../Taskfile.yml)
- SOPS workflow tasks: [`.taskfiles/sops/tasks.yaml`](../../.taskfiles/sops/tasks.yaml)
- Example monitoring playbook:
  [`cluster/apps/observability/victoria-metrics-k8s-stack/README.md`](observability/victoria-metrics-k8s-stack/README.md)

## Change Log

- _TBD — record future updates to this runbook here (yyyy-mm-dd · short summary ·
  link to PR)._
