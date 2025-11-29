# technitium-secondary Runbook

## Purpose and Scope

Technitium-secondary is a secondary DNS server deployment using the Technitium DNS Server, providing DNS resolution services as a backup to the primary DNS server. This readme documents the GitOps layout, deployment workflow, and operations for maintaining the secondary DNS server in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                            | Description                                                                |
| ------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/technitium/technitium-secondary/README.md`                        | This runbook and component overview.                                       |
| `cluster/apps/technitium/kustomization.yaml`                                    | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/technitium/namespace.yaml`                                        | Namespace definition for the technitium workload.                          |
| `cluster/apps/technitium/technitium-secondary/ks.yaml`                          | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/technitium/technitium-secondary/app/kustomization.yaml`           | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/technitium/technitium-secondary/app/release.yaml`                 | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.          |
| `cluster/apps/technitium/technitium-secondary/app/values.yaml`                  | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/technitium/technitium-secondary/app/certificate.yaml`             | Certificate resource for TLS termination.                                  |
| `cluster/apps/technitium/technitium-secondary/app/persistent-volume-claim.yaml` | PVC for DNS configuration persistence.                                     |
| `cluster/apps/technitium/technitium-secondary/app/pod-disruption-budget.yaml`   | PDB ensuring availability during updates.                                  |
| `cluster/flux/meta/repositories/helm/bjw-s-charts.yaml`                         | Helm repository definition pinning the upstream app-template source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage DNS services.
- Ensure the workstation can reach the Kubernetes API and that the `technitium-secondary` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- DNS secrets (admin password) must be available via external-secrets or SOPS.

## Operational Runbook

### Summary

Operate the technitium-secondary Helm release to provide secondary DNS resolution services, including DNS over TLS/HTTPS and API access.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when DNS changes could impact service availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n technitium get helmrelease technitium-secondary -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/technitium/technitium-secondary/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr technitium-secondary --namespace technitium
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization technitium-secondary --with-source
   flux get kustomizations technitium-secondary -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease technitium-secondary -n technitium
   ```

#### Phase 3 – Monitor DNS Services

1. Watch pod status and logs:

   ```bash
   kubectl get pods -n technitium -l app.kubernetes.io/name=technitium-secondary
   kubectl logs -n technitium deployment/technitium-secondary
   ```

2. Validate DNS resolution:

   ```bash
   nslookup example.com <secondary-dns-ip>
   ```

3. Check service endpoints:

   ```bash
   kubectl get svc -n technitium technitium-secondary-dns
   ```

#### Phase 4 – Manual Intervention for DNS Issues

1. Check DNS server health via API or logs.
2. Verify zone transfers from primary DNS server.
3. Inspect certificate validity for DoT/DoH.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization technitium-secondary -n flux-system
   flux suspend helmrelease technitium-secondary -n technitium
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization technitium-secondary -n flux-system
   flux resume helmrelease technitium-secondary -n technitium
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n technitium scale deploy/technitium-secondary --replicas=0
   ```

### Validation

- `kubectl get pods -n technitium` shows technitium-secondary pods in Running state.
- `kubectl get svc -n technitium` shows DNS services with assigned IPs.
- `flux get helmrelease technitium-secondary -n technitium` reports `Ready=True` with no pending upgrades.
- DNS queries resolve successfully against the secondary server.

### Troubleshooting Guidance

- If DNS queries fail, check pod logs and network connectivity.
- For certificate issues, verify cert-manager status and DNS-01 challenges.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr technitium-secondary --namespace technitium
  kubeconform -strict -summary ./cluster/apps/technitium/technitium-secondary/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                       | Purpose                                                                                          |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                            | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                        | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr technitium-secondary --namespace technitium` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get pods -n technitium`                           | Validates pod deployment and readiness.                                                          |
| `nslookup` against service IP                              | Ensures DNS resolution functionality.                                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](/cluster/apps/flux-system/flux-instance/README.md)
- DNS management: [cluster/apps/README.md](/cluster/apps/README.md)
- Technitium DNS Server documentation: <https://technitium.com/dns/>
- bjw-s app-template Helm chart: <https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common>
