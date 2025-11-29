# external-secrets Runbook

## Purpose and Scope

The external-secrets deployment provides a Kubernetes operator for managing secrets from external sources like AWS Secrets Manager, HashiCorp Vault, etc. This runbook documents the GitOps layout, deployment workflow, and operations required to keep secret synchronization healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                                 | Description                                                                |
| ------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| `cluster/apps/external-secrets/external-secrets/README.md`                           | This runbook and component overview.                                       |
| `cluster/apps/external-secrets/kustomization.yaml`                                   | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/external-secrets/namespace.yaml`                                       | Namespace definition for the external-secrets workload.                    |
| `cluster/apps/external-secrets/external-secrets/ks.yaml`                             | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/external-secrets/external-secrets/app/kustomization.yaml`              | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/external-secrets/external-secrets/app/release.yaml`                    | Flux `HelmRelease` referencing the external-secrets chart.                 |
| `cluster/apps/external-secrets/external-secrets/app/values.yaml`                     | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/external-secrets/external-secrets/app/kustomizeconfig.yaml`            | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/apps/external-secrets/external-secrets/resources/cluster-rbac.yaml`         | Cluster-scoped RBAC for the operator.                                      |
| `cluster/apps/external-secrets/external-secrets/resources/cluster-secret-store.yaml` | ClusterSecretStore configuration.                                          |
| `cluster/flux/meta/repositories/helm/external-secrets.yaml`                          | Helm repository definition pinning the upstream external-secrets source.   |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage external secret stores.
- Ensure the workstation can reach the Kubernetes API and that the `external-secrets` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the external-secrets Helm release to synchronize secrets from external providers into Kubernetes secrets.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when secret changes could impact applications.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n external-secrets get helmrelease external-secrets -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/external-secrets/external-secrets/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr external-secrets --namespace external-secrets
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization external-secrets --with-source
   flux get kustomizations external-secrets -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease external-secrets -n external-secrets
   ```

#### Phase 3 – Monitor Secret Synchronization

1. Watch external-secrets pods and CRDs:

   ```bash
   kubectl get pods -n external-secrets
   kubectl get crd | grep external-secrets
   ```

2. Validate SecretStores and ExternalSecrets are created.
3. Ensure secrets are populated.

#### Phase 4 – Manual Intervention for Secret Issues

1. Restart the deployment if synchronization fails:

   ```bash
   kubectl -n external-secrets rollout restart deploy/external-secrets
   ```

2. For provider credentials issues, verify secrets are correct.
3. Inspect logs for synchronization errors:

   ```bash
   kubectl logs -n external-secrets deploy/external-secrets
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization external-secrets -n flux-system
   flux suspend helmrelease external-secrets -n external-secrets
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization external-secrets -n flux-system
   flux resume helmrelease external-secrets -n external-secrets
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n external-secrets scale deploy/external-secrets --replicas=0
   ```

### Validation

- `kubectl get pods -n external-secrets` shows running pods with no restarts.
- `kubectl get helmrelease external-secrets -n external-secrets` reports `Ready=True` with no pending upgrades.
- CRDs are installed and SecretStores can be created.
- Secrets are synchronized from external providers.

### Troubleshooting Guidance

- If synchronization fails, check provider credentials and connectivity.
- For CRD issues, ensure the operator is running and has permissions.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr external-secrets --namespace external-secrets
  kubeconform -strict -summary ./cluster/apps/external-secrets/external-secrets/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n external-secrets get pods
  kubectl -n external-secrets describe pod <pod-name>
  ```

- For secret issues, consult external-secrets documentation.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                              | Purpose                                                                                          |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------------------- |
| `task validate`                                                   | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                               | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr external-secrets --namespace external-secrets`      | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n external-secrets get events --sort-by=.lastTimestamp` | Confirms the operator starts reconciling after rollout.                                          |
| `kubectl get crd                                                  | grep external-secrets`                                                                           | Validates that CRDs are installed. |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Certificate management: [cluster/apps/README.md](../../README.md)
- Upstream external-secrets documentation: <https://external-secrets.io/>

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of external-secrets tasks, focusing on secret synchronization and error handling.

### Secret Synchronization Status Workflow

```bash
If kubectl get externalsecrets -A --no-headers | grep -v "SecretSynced" > /dev/null
Then:
  For each failing ExternalSecret:
    Run kubectl describe externalsecret <name> -n <namespace>
    Expected output: Sync status and conditions
    If status shows "SecretSyncedError":
      Run kubectl get secret <secret-name> -n <namespace>
      Expected output: Secret exists or not
      If secret missing:
        Run kubectl logs -n external-secrets deployment/external-secrets | grep <externalsecret-name>
        Expected output: Sync error logs
        Recovery: Verify SecretStore configuration and provider access
      Else:
        Run kubectl get events -n <namespace> --field-selector involvedObject.name=<externalsecret-name>
        Expected output: Related events
        Recovery: Check provider credentials; ensure dataFrom paths are correct
  Else:
    Proceed to SecretStore health check
Else:
  Proceed to SecretStore health check
```

### SecretStore Connectivity Workflow

```bash
If kubectl get secretstores -A --no-headers | grep -v "Valid" > /dev/null
Then:
  For each invalid SecretStore:
    Run kubectl describe secretstore <name> -n <namespace>
    Expected output: Store status and validation errors
    If AWS provider failing:
      Run kubectl get secret <aws-secret> -n <namespace>
      Expected output: AWS credentials present
      Recovery: Verify IAM permissions; check region configuration
    Else if Vault provider failing:
      Run kubectl logs -n external-secrets deployment/external-secrets | grep vault
      Expected output: Authentication errors
      Recovery: Check Vault token/approle; verify CA certificates
  Else:
    Secret synchronization verified successfully
Else:
  Secret synchronization verified successfully
```

### Synchronization Failure Recovery Workflow

```bash
If kubectl get externalsecrets -A -o jsonpath='{.items[?(@.status.conditions[?(@.type=="SecretSyncedError")].status=="True")].metadata.name}' | grep . > /dev/null
Then:
  For each ExternalSecret with sync errors:
    Run kubectl get externalsecret <name> -n <namespace> -o yaml | grep -A 10 status
    Expected output: Detailed error conditions
    If refresh interval exceeded:
      Run kubectl annotate externalsecret <name> -n <namespace> force-sync.external-secrets.io/reason="manual-trigger"
      Expected output: Annotation added
      Recovery: Triggers immediate sync attempt
    Else if provider rate limited:
      Run kubectl logs -n external-secrets deployment/external-secrets --since=5m | grep rate
      Expected output: Rate limit messages
      Recovery: Wait for rate limit reset; consider increasing intervals
  Else:
    External secrets healthy
Else:
  External secrets healthy
```
