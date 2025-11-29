# victoria-metrics-secret-writer Runbook

## Purpose and Scope

The victoria-metrics-secret-writer controller deploys a Kubernetes Job that extracts etcd TLS certificates from control-plane nodes and creates a secret for Victoria Metrics operator to securely access etcd metrics.

This enables monitoring of etcd performance and health in the spruyt-labs environment. This readme documents the GitOps layout, deployment workflow, and operations required to keep the secret writer functional.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                                    | Description                                                                |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/observability/victoria-metrics-secret-writer/README.md`                   | Parent runbook and component overview.                                     |
| `cluster/apps/observability/kustomization.yaml`                                         | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/observability/namespace.yaml`                                             | Namespace definition for the observability workload.                       |
| `cluster/apps/observability/victoria-metrics-secret-writer/ks.yaml`                     | Flux `Kustomization` driving reconciliation of the manifests.              |
| `cluster/apps/observability/victoria-metrics-secret-writer/app/kustomization.yaml`      | Overlay combining the Job and RBAC resources.                              |
| `cluster/apps/observability/victoria-metrics-secret-writer/app/role.yaml`               | RBAC role for secret creation permissions.                                 |
| `cluster/apps/observability/victoria-metrics-secret-writer/app/service-account.yaml`    | Service account for the Job.                                               |
| `cluster/apps/observability/victoria-metrics-secret-writer/app/role-binding.yaml`       | Binding role to service account.                                           |
| `cluster/apps/observability/victoria-metrics-secret-writer/app/etcd-secret-writer.yaml` | Job definition for extracting and creating etcd secrets.                   |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage secrets and RBAC in observability namespace.
- Ensure the workstation can reach the Kubernetes API and that the `victoria-metrics-secret-writer` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Verify that etcd certificates exist on control-plane nodes at `/system/secrets/etcd/`.

## Operational Runbook

### Summary

Operate the victoria-metrics-secret-writer Job to ensure etcd TLS certificates are available as Kubernetes secrets for Victoria Metrics monitoring.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`).
- Identify maintenance windows when secret recreation could impact monitoring.
- Capture the current Job status for reference:

  ```bash
  kubectl -n observability get job etcd-secret-writer -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update manifests under `cluster/apps/observability/victoria-metrics-secret-writer/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs:

   ```bash
   flux diff ks victoria-metrics-secret-writer --path=./cluster/apps/observability/victoria-metrics-secret-writer
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization victoria-metrics-secret-writer --with-source
   flux get kustomizations victoria-metrics-secret-writer -n flux-system
   ```

2. Confirm the Job executed successfully:

   ```bash
   kubectl -n observability get job etcd-secret-writer
   ```

#### Phase 3 – Monitor Secret Creation

1. Watch Job logs for execution status:

   ```bash
   kubectl logs -n observability job/etcd-secret-writer
   ```

2. Validate secret creation:

   ```bash
   kubectl get secret etcd-secrets -n observability
   kubectl describe secret etcd-secrets -n observability
   ```

3. Check RBAC permissions if Job fails.

#### Phase 4 – Manual Intervention for Issues

1. Delete and recreate the Job if it failed:

   ```bash
   kubectl delete job etcd-secret-writer -n observability
   flux reconcile kustomization victoria-metrics-secret-writer --with-source
   ```

2. Inspect service account and role bindings:

   ```bash
   kubectl auth can-i create secrets --as system:serviceaccount:observability:secrets-writer
   ```

3. Verify etcd certificate paths on control-plane nodes.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization victoria-metrics-secret-writer -n flux-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization victoria-metrics-secret-writer -n flux-system
   ```

4. Delete the secret manually if needed:

   ```bash
   kubectl delete secret etcd-secrets -n observability
   ```

### Validation

- `kubectl get job etcd-secret-writer -n observability` shows Job completed successfully.
- `kubectl get secret etcd-secrets -n observability` exists with etcd certificate data.
- Victoria Metrics operator can access etcd metrics using the secret.
- No errors in Job logs.

### Troubleshooting Guidance

- If Job fails, check control-plane node access and certificate file existence.
- For permission denied, verify RBAC role and service account configuration.
- When secret is not created, inspect Job logs for kubectl command errors.
- If etcd certificates change, re-run the Job to update the secret.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                           | Purpose                                                              |
| -------------------------------------------------------------- | -------------------------------------------------------------------- |
| `task validate`                                                | Runs repository schema validation (kubeconform, yamllint, conftest). |
| `task dev-env:lint`                                            | Executes markdownlint, prettier, and ancillary linters.              |
| `flux diff ks victoria-metrics-secret-writer`                  | Previews Kustomize changes before reconciliation.                    |
| `kubectl -n observability get events --sort-by=.lastTimestamp` | Confirms Job execution events.                                       |
| `kubectl get secret etcd-secrets -n observability`             | Validates secret creation with certificate data.                     |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Victoria Metrics operator: [cluster/apps/observability/victoria-metrics-operator/README.md](../victoria-metrics-operator/README.md)
- etcd monitoring: <https://etcd.io/docs/v3.5/op-guide/monitoring/>
- Kubernetes Jobs: <https://kubernetes.io/docs/concepts/workloads/controllers/job/>
