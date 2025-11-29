# kubelet-csr-approver Runbook

## Purpose and Scope

The kubelet-csr-approver controller automates approval of node client
certificates. It enforces policy checks before Talos-managed worker and
control-plane nodes join the cluster. This readme documents the GitOps layout,
deployment workflow, and operations required to keep the automation healthy for
the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and
  remediation.
- Capture validation, troubleshooting, and references that align with the root
  runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                              | Description                                                                  |
| --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `cluster/kubelet-csr-approver/README.md`                                          | This runbook and component overview.                                         |
| `cluster/apps/kubelet-csr-approver/kustomization.yaml`                            | Top-level Kustomize entry that namespaces resources and delegates to Flux.   |
| `cluster/apps/kubelet-csr-approver/namespace.yaml`                                | Namespace definition for the controller workload.                            |
| `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.      |
| `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.            |
| `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/release.yaml`         | Flux `HelmRelease` referencing the upstream PostFinance chart.               |
| `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                         |
| `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.              |
| `cluster/flux/meta/repositories/helm/postfinance-charts.yaml`                     | Helm repository definition pinning the upstream kubelet-csr-approver source. |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`,
  and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to approve CSRs.
- Ensure the workstation can reach the Kubernetes API and that the
  `kubelet-csr-approver` Flux objects are not suspended
  (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the kubelet-csr-approver Helm release so kubelet client certificate
signing requests are automatically validated and approved, keeping Talos nodes
Ready without manual intervention.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature
  branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`,
  `flux get helmreleases -A`).
- Identify maintenance windows when approving or denying CSRs could impact node
  availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n kubelet-csr-approver get helmrelease kubelet-csr-approver -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under
   `cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to
   confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr kubelet-csr-approver --namespace kubelet-csr-approver
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization kubelet-csr-approver --with-source
   flux get kustomizations kubelet-csr-approver -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease kubelet-csr-approver -n kubelet-csr-approver
   ```

#### Phase 3 – Monitor CSR Approvals

1. Watch incoming CSRs while nodes bootstrap:

   ```bash
   kubectl get csr
   kubectl describe csr <name>
   ```

2. Validate events emitted by the controller:

   ```bash
   kubectl get events -n kubelet-csr-approver --sort-by=.lastTimestamp
   ```

3. Ensure newly joined nodes reach Ready state (`kubectl get nodes`,
   `talosctl health`).

#### Phase 4 – Manual Intervention for Stuck CSRs

1. Approve urgent CSRs manually if automation is degraded:

   ```bash
   kubectl certificate approve <csr-name>
   ```

2. For security-sensitive cases, deny the CSR and investigate node identity:

   ```bash
   kubectl certificate deny <csr-name>
   ```

3. Inspect controller logs for policy failures or RBAC errors:

   ```bash
   kubectl logs -n kubelet-csr-approver deploy/kubelet-csr-approver
   ```

4. Rotate Talos bootstrap tokens if repeated unknown CSRs appear.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior
   state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization kubelet-csr-approver -n flux-system
   flux suspend helmrelease kubelet-csr-approver -n kubelet-csr-approver
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization kubelet-csr-approver -n flux-system
   flux resume helmrelease kubelet-csr-approver -n kubelet-csr-approver
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n kubelet-csr-approver scale deploy kubelet-csr-approver --replicas=0
   ```

### Validation

- `kubectl get csr` shows new requests transitioning to `Approved,Issued` within
  seconds of submission.
- `kubectl get nodes` reports joining nodes as `Ready` with current CSR issuance
  timestamps.
- `flux get helmrelease kubelet-csr-approver -n kubelet-csr-approver` reports
  `Ready=True` with no pending upgrades.
- Audit logs confirm the controller approved CSRs instead of manual
  administrators.

### Troubleshooting Guidance

- If CSRs remain pending, inspect controller logs for policy violations and
  verify RBAC:

  ```bash
  kubectl auth can-i approve certificatesigningrequests.nodeclient \
    --as system:serviceaccount:kubelet-csr-approver:kubelet-csr-approver
  ```

- For repeated denials, ensure Talos node configurations present expected SANs
  and group memberships.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr kubelet-csr-approver --namespace kubelet-csr-approver
  kubeconform -strict -summary \
    ./cluster/apps/kubelet-csr-approver/kubelet-csr-approver/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n kubelet-csr-approver get pods
  kubectl -n kubelet-csr-approver describe pod <pod-name>
  ```

- For Talos nodes failing to request certificates, consult
  `talosctl -n <node> logs kubelet` for client-side errors.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                                  | Purpose                                                                                          |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                       | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                                   | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr kubelet-csr-approver --namespace kubelet-csr-approver`  | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n kubelet-csr-approver get events --sort-by=.lastTimestamp` | Confirms the controller emits approval events after rollout.                                     |
| `kubectl get nodes`                                                   | Validates that approved CSRs translate into Ready nodes.                                         |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](/cluster/flux/README.md)
- CSR policy and security context: [cluster/crds/README.md](/cluster/apps/crds/README.md)
- Talos node bootstrap procedures: [talos/README.md](/cluster/talos/README.md)
- Upstream kubelet-csr-approver documentation:
  <https://github.com/postfinance/kubelet-csr-approver>
- Kubernetes certificate signing requests reference:
  <https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/>
