# external-dns-technitium Runbook

## Purpose and Scope

The external-dns-technitium deployment provides external DNS management for Kubernetes services and ingresses using the Technitium DNS server via RFC2136. This runbook documents the GitOps layout, deployment workflow, and operations required to keep DNS synchronization healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                         | Description                                                                |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/external-dns/README.md`                                        | This runbook and component overview.                                       |
| `cluster/apps/external-dns/kustomization.yaml`                               | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/external-dns/namespace.yaml`                                   | Namespace definition for the external-dns workload.                        |
| `cluster/apps/external-dns/external-dns-technitium/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/external-dns/external-dns-technitium/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/external-dns/external-dns-technitium/app/release.yaml`         | Flux `HelmRelease` referencing the external-dns chart.                     |
| `cluster/apps/external-dns/external-dns-technitium/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/external-dns/external-dns-technitium/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/helm/external-dns.yaml`                      | Helm repository definition pinning the upstream external-dns source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage DNS records.
- Ensure the workstation can reach the Kubernetes API and that the `external-dns-technitium` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the external-dns-technitium Helm release to automatically manage DNS records for Kubernetes services and ingresses using Technitium DNS server.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when DNS changes could impact service availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n external-dns get helmrelease external-dns-technitium -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/external-dns/external-dns-technitium/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr external-dns-technitium --namespace external-dns
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization external-dns-technitium --with-source
   flux get kustomizations external-dns-technitium -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease external-dns-technitium -n external-dns
   ```

#### Phase 3 – Monitor DNS Synchronization

1. Watch external-dns pods and logs:

   ```bash
   kubectl get pods -n external-dns
   kubectl logs -n external-dns deploy/external-dns-technitium
   ```

2. Validate DNS records are created/updated in Technitium.
3. Ensure services are resolvable.

#### Phase 4 – Manual Intervention for DNS Issues

1. Restart the deployment if synchronization fails:

   ```bash
   kubectl -n external-dns rollout restart deploy/external-dns-technitium
   ```

2. For TSIG key issues, verify secrets are correct.
3. Inspect logs for DNS update errors:

   ```bash
   kubectl logs -n external-dns deploy/external-dns-technitium
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization external-dns-technitium -n flux-system
   flux suspend helmrelease external-dns-technitium -n external-dns
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization external-dns-technitium -n flux-system
   flux resume helmrelease external-dns-technitium -n external-dns
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n external-dns scale deploy/external-dns-technitium --replicas=0
   ```

### Validation

- `kubectl get pods -n external-dns` shows running pods with no restarts.
- `kubectl get helmrelease external-dns-technitium -n external-dns` reports `Ready=True` with no pending upgrades.
- DNS records are created for services with annotations.
- Services are resolvable via DNS.

### Troubleshooting Guidance

- If DNS updates fail, check TSIG keys and Technitium server connectivity.
- For annotation issues, ensure services have correct external-dns annotations.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr external-dns-technitium --namespace external-dns
  kubeconform -strict -summary ./cluster/apps/external-dns/external-dns-technitium/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n external-dns get pods
  kubectl -n external-dns describe pod <pod-name>
  ```

- For DNS issues, consult external-dns and Technitium documentation.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                            | Purpose                                                                                          |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                 | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                             | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr external-dns-technitium --namespace external-dns` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n external-dns get events --sort-by=.lastTimestamp`   | Confirms DNS synchronization starts after rollout.                                               |
| `kubectl get pods -n external-dns`                              | Validates that the deployment is running and healthy.                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../flux/README.md)
- Certificate management: [cluster/apps/README.md](../../README.md)
- Upstream external-dns documentation: <https://github.com/kubernetes-sigs/external-dns>
- Technitium DNS documentation: <https://technitium.com/dns/>
