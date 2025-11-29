# cert-manager Runbook

## Purpose and Scope

Cert-manager is a Kubernetes add-on to automate the management and issuance of TLS certificates from various issuing sources, including Let's Encrypt, HashiCorp Vault, and Venafi. This readme documents the GitOps layout, deployment workflow, and operations for maintaining cert-manager in spruyt-labs.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/cert-manager/cert-manager/README.md`                | This runbook and component overview.                                       |
| `cluster/apps/cert-manager/kustomization.yaml`                    | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/cert-manager/namespace.yaml`                        | Namespace definition for the cert-manager workload.                        |
| `cluster/apps/cert-manager/cert-manager/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/cert-manager/cert-manager/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/cert-manager/cert-manager/app/release.yaml`         | Flux `HelmRelease` referencing the upstream jetstack/cert-manager chart.   |
| `cluster/apps/cert-manager/cert-manager/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/cert-manager/cert-manager/app/cluster-issuers.yaml` | ClusterIssuer resources for ACME certificate issuance.                     |
| `cluster/apps/cert-manager/cert-manager/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/helm/jetstack-charts.yaml`        | Helm repository definition pinning the upstream cert-manager source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage certificate issuers.
- Ensure the workstation can reach the Kubernetes API and that the `cert-manager` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- DNS-01 challenge requires Cloudflare API token and domain access for ACME issuance.

## Operational Runbook

### Summary

Operate the cert-manager Helm release to provide automated certificate lifecycle management, including issuance, renewal, and revocation for TLS certificates used across the cluster.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when certificate changes could impact service availability.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n cert-manager get helmrelease cert-manager -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/cert-manager/cert-manager/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr cert-manager --namespace cert-manager
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization cert-manager --with-source
   flux get kustomizations cert-manager -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease cert-manager -n cert-manager
   ```

#### Phase 3 – Monitor Certificate Issuance

1. Watch certificate requests and issuances:

   ```bash
   kubectl get certificates -A
   kubectl get certificaterequests -A
   ```

2. Validate ClusterIssuer status:

   ```bash
   kubectl get clusterissuers
   kubectl describe clusterissuer letsencrypt-production
   ```

3. Ensure certificates are renewed before expiration.

#### Phase 4 – Manual Intervention for Failed Issuances

1. Check certificate request status for errors:

   ```bash
   kubectl describe certificaterequest <name>
   ```

2. Verify DNS propagation for DNS-01 challenges.
3. Inspect cert-manager logs for ACME errors:

   ```bash
   kubectl logs -n cert-manager deployment/cert-manager
   ```

4. For stuck requests, delete and recreate the Certificate resource.

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization cert-manager -n flux-system
   flux suspend helmrelease cert-manager -n cert-manager
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization cert-manager -n flux-system
   flux resume helmrelease cert-manager -n cert-manager
   ```

4. Scale deployments to zero as a last resort:

   ```bash
   kubectl -n cert-manager scale deploy/cert-manager --replicas=0
   kubectl -n cert-manager scale deploy/cert-manager-cainjector --replicas=0
   kubectl -n cert-manager scale deploy/cert-manager-webhook --replicas=0
   ```

### Validation

- `kubectl get certificates -A` shows certificates in Ready state with valid expiration dates.
- `kubectl get clusterissuers` reports all issuers as Ready.
- `flux get helmrelease cert-manager -n cert-manager` reports `Ready=True` with no pending upgrades.
- Certificate secrets are present and contain valid TLS data.

### Troubleshooting Guidance

- If certificates fail to issue, check DNS resolution and Cloudflare API access.
- For webhook errors, ensure CRDs are installed and webhook is reachable.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr cert-manager --namespace cert-manager
  kubeconform -strict -summary ./cluster/apps/cert-manager/cert-manager/app
  ```

- If pods crash, inspect logs and resource limits.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                 | Purpose                                                                                          |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                      | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                  | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr cert-manager --namespace cert-manager` | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl get certificates -A`                        | Validates certificate issuance and renewal.                                                      |
| `kubectl get clusterissuers`                         | Ensures issuers are operational.                                                                 |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Certificate management: [cluster/apps/README.md](../../README.md)
- Upstream cert-manager documentation: <https://cert-manager.io/docs/>
- Jetstack cert-manager Helm chart: <https://github.com/cert-manager/cert-manager/tree/master/deploy/charts/cert-manager>
- ACME protocol: <https://tools.ietf.org/html/rfc8555>

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of cert-manager tasks, including certificate issuance checks and recovery from failures.

### Certificate Issuance Status Workflow

```bash
If kubectl get certificates -A --no-headers | grep -v "True" > /dev/null
Then:
  For each failing certificate:
    Run kubectl describe certificate <name> -n <namespace>
    Expected output: Certificate status and events
    If status shows "False":
      Run kubectl get certificaterequests -n <namespace> | grep <certificate-name>
      Expected output: Associated CertificateRequest
      If CertificateRequest exists:
        Run kubectl describe certificaterequest <request-name> -n <namespace>
        Expected output: Request status and failure reason
        Recovery: Check DNS propagation; verify issuer credentials
      Else:
        Run kubectl logs -n cert-manager deployment/cert-manager
        Expected output: Controller logs for issuance errors
        Recovery: Ensure ClusterIssuer is properly configured
  Else:
    Proceed to issuer health check
Else:
  Proceed to issuer health check
```

### ClusterIssuer Health Workflow

```bash
If kubectl get clusterissuers --no-headers | grep -v "True" > /dev/null
Then:
  For each failing issuer:
    Run kubectl describe clusterissuer <name>
    Expected output: Issuer status and conditions
    If ACME issuer failing:
      Run kubectl logs -n cert-manager deployment/cert-manager | grep <issuer-name>
      Expected output: ACME challenge errors
      Recovery: Verify DNS-01 challenge configuration; check Cloudflare API access
    Else if CA issuer failing:
      Run kubectl get secret <ca-secret> -n cert-manager
      Expected output: CA certificate present
      Recovery: Ensure CA certificate is valid and accessible
  Else:
    Certificates verified successfully
Else:
  Certificates verified successfully
```

### Certificate Renewal Failure Recovery Workflow

```bash
If kubectl get certificates -A -o jsonpath='{.items[?(@.status.renewalTime<"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'")].metadata.name}' | grep . > /dev/null
Then:
  For each certificate nearing expiration:
    Run kubectl get certificate <name> -n <namespace> -o yaml | grep renewalTime
    Expected output: Renewal time before current time
    If renewal failed:
      Run kubectl delete certificaterequest <request-name> -n <namespace>
      Expected output: Request deleted
      Recovery: Wait for automatic re-issuance; check issuer rate limits
    Else:
      Run kubectl annotate certificate <name> -n <namespace> cert-manager.io/issue-temporary-certificate=true
      Expected output: Annotation added
      Recovery: Forces immediate renewal attempt
  Else:
    Certificate lifecycle healthy
Else:
  Certificate lifecycle healthy
```
