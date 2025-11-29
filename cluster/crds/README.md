# Custom Resource Definitions Runbook

## Purpose and Scope

This runbook covers authoring, validation, deployment, and rollback of custom
resource definitions (CRDs) that support FluxCD-managed workloads in the
spruyt-labs cluster. It follows the repository runbook standards and clarifies
how operator-managed CRDs coexist with Helm-managed and Talos-provisioned
manifests.

## Directory Layout

While Talos extra manifests and Helm automation install most CRDs today, the
structure below reserves space for operator-authored definitions and supporting
artifacts.

<!-- markdownlint-disable MD013 -->

| Path                                               | Purpose                                                                                                   |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `cluster/crds/`                                    | CRD lifecycle documentation and shared metadata (this runbook).                                           |
| `cluster/crds/<provider>/`                         | Optional provider folders for curated CRD overlays and policy notes.                                      |
| `cluster/crds/<provider>/schemas/`                 | Generated OpenAPI or JSON schema exports for kubeconform and IDE validation.                              |
| `talos/patches/control-plane/extra-manifests.yaml` | Talos extra manifests that deliver foundational CRDs (Gateway API, Prometheus Operator, CSI snapshotter). |
| `cluster/apps/**/resources/`                       | Flux-managed CRDs or other cluster-scoped resources bundled with workloads.                               |

<!-- markdownlint-enable MD013 -->

## Operational Runbook

### Summary

Maintain CRD compatibility by coordinating schema changes, enforcing validation,
and deploying through Flux or Talos workflows without disrupting dependent
workloads.

### Preconditions

- Use the repository devcontainer or ensure `flux`, `kubectl`, `kubeconform`,
  `talosctl`, `task`, and `sops` are installed.
- Sync with the latest `main` branch and confirm no Flux suspensions block CRD
  delivery.
- For Talos-managed CRDs, ensure access to `talosconfig` and Talhelper
  credentials.
- Document intended CRD changes (group, versions, breaking semantics) in the
  related workload readme and reference this runbook in the pull request.

### Procedure

#### Phase 1 – Assess Impact

1. Inventory affected resources. Examples:
   - `kubectl get crds | grep <group>` to list versions.
   - `kubectl describe crd <resource>` to review served and storage versions.
2. Select a delivery path:
   - **Talos extra manifests** for cluster-wide controllers required before Flux.
   - **Helm/Flux-managed manifests** when vendors ship CRDs with their charts.
   - **Manual overlays under `cluster/crds/`** for bespoke or patched CRDs.

#### Phase 2 – Author and Review

1. Update `talos/patches/control-plane/extra-manifests.yaml` when Talos should
   deliver CRDs. Pin URLs to release tags for reproducibility.
2. For Flux-managed CRDs, place manifests in
   `cluster/apps/<namespace>/<app>/resources/` and verify reconciliation order
   (CRDs before dependent HelmRelease objects).
3. For manually managed CRDs:
   - Commit YAML under `cluster/crds/<provider>/`.
   - Generate optional schemas under `cluster/crds/<provider>/schemas/`.
   - Start from the baseline template below.

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: widgets.example.com
spec:
  group: example.com
  scope: Namespaced
  names:
    kind: Widget
    plural: widgets
  versions:
    - name: v1alpha1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required:
                - size
              properties:
                size:
                  type: string
                  enum:
                    - small
                    - large
```

1. Capture compatibility considerations (removed versions, conversion webhook
   requirements) in the pull request description.

#### Phase 3 – Validate

1. Run `task dev-env:lint` to execute markdownlint, yamllint, prettier, and
   gitleaks checks.
2. Validate schema compliance with `kubeconform --summary` against modified
   directories, for example:
   - `kubeconform --summary cluster/crds`
   - `kubeconform --summary cluster/apps/<namespace>/<app>/resources`
3. Regenerate Talos machine configs with `task talos:gen` and inspect diffs.
4. Confirm GitHub Actions `lint.yaml` and `flux-differ.yaml` complete
   successfully.

#### Phase 4 – Deploy

1. **Talos path**
   - Regenerate configs: `task talos:gen`.
   - Apply changes: `task talos:apply`, `task talos:apply-c[1-3]`, or
     `task talos:apply-w[1-3]`.
   - Monitor health: `talosctl health`, `talosctl -n <node> logs kubelet`.
2. **Flux path**
   - Commit CRDs and ensure they reconcile ahead of dependent workloads.
   - Preview changes: `flux diff ks <name> --path=./cluster/apps/<namespace>/<app>`.
   - Force reconciliation: `flux reconcile kustomization <name> --with-source`.
   - Check readiness:
     - `flux get kustomizations -n flux-system`
     - `flux get helmreleases -n <namespace>`
3. **Post-apply validation**
   - `kubectl get crds <resource> -o yaml | yq '.spec.versions'`
   - `kubectl get <custom-resource>` for representative instances.

#### Phase 5 – Rollback

1. **Talos-managed CRDs**: revert the manifest URL, regenerate configs, and
   reapply with the Talos tasks listed above.
2. **Flux-managed CRDs**
   - `git revert <commit>` to restore the previous definition.
   - `flux suspend kustomization <name>` if incompatibility causes reconciliation
     loops, then resume after remediation.
3. Verify that custom resources remain compatible with the reverted schema before
   re-enabling controllers.

### Validation and Testing

- `task dev-env:lint` – repository-wide linting prior to PR.
- `kubeconform --summary` – schema validation of CRD directories.
- GitHub Actions `lint.yaml` – Markdown, YAML, JSON, and policy checks.
- GitHub Actions `flux-differ.yaml` – ensures Flux diffs and reconciliation align
  with expectations.
- `talosctl health` – validates Talos-applied CRDs do not impact control-plane
  readiness.
- `flux logs --kind Kustomization --name <name> -n flux-system` – verifies Flux
  reconciliation state after CRD updates.

### Troubleshooting

<!-- markdownlint-disable MD013 -->

| Failure Mode                               | Diagnostics                                                                                                          | Remediation                                                                                                           |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Flux reconciliation fails after CRD update | `flux get kustomizations -n flux-system`, `flux logs --kind Kustomization --name <name> -n flux-system`              | Confirm CRDs reconcile before dependent workloads, apply CRDs manually with `kubectl apply -f`, or revert the change. |
| Incompatible custom resource schema        | `kubectl describe crd <resource>`, `kubectl get <resource> -A -o yaml \| yq`                                         | Run conversion scripts, restore compatibility fields, or roll back until data migration completes.                    |
| API version deprecation warnings           | `kubectl get events -A \| grep Deprecated`, `kubectl get --raw /metrics \| grep apiserver_requested_deprecated_apis` | Add newer versions to the CRD, migrate workloads, and remove deprecated versions only after migration succeeds.       |
| Talos extra manifests drift                | `talhelper genconfig --diff`, `talosctl -n <node> get appliedconfiguration`                                          | Reapply machine configs, verify manifest URLs, and confirm Talos hosts can reach upstream sources.                    |
| Snapshot controller missing CRDs           | `kubectl get crds \| grep snapshot.storage.k8s.io`, `kubectl logs -n kube-system deploy/snapshot-controller`         | Reapply Talos manifests or fetch CRDs from the upstream external snapshotter release, then restart controllers.       |

<!-- markdownlint-enable MD013 -->

### References and Cross-links

- Repository runbook standards: [`README.md`](../../README.md#runbook-standards)
- Flux operations guide: [`cluster/flux/README.md`](../flux/README.md)
- Talos extra manifests configuration:
  [`talos/patches/control-plane/extra-manifests.yaml`](../../talos/patches/control-plane/extra-manifests.yaml)
- Flux task automation: [`Taskfile.yml`](../../Taskfile.yml)
- Application runbook example: [`cluster/apps/README.md`](../apps/README.md)
