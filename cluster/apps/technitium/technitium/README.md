# Technitium DNS Server Runbook

## Purpose and Scope

The Technitium DNS Server provides authoritative and recursive DNS services, supporting standard DNS queries, DNS over TLS (DoT), DNS over HTTPS (DoH), and a web-based API for configuration and management. This readme documents the GitOps layout, deployment workflow, and operations required to keep the DNS services healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                  | Description                                                                |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/technitium/README.md`                                   | This runbook and component overview.                                       |
| `cluster/apps/technitium/kustomization.yaml`                          | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/technitium/namespace.yaml`                              | Namespace definition for the DNS server workload.                          |
| `cluster/apps/technitium/technitium/ks.yaml`                          | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/technitium/technitium/app/kustomization.yaml`           | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/technitium/technitium/app/release.yaml`                 | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.          |
| `cluster/apps/technitium/technitium/app/values.yaml`                  | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/technitium/technitium/app/kustomizeconfig.yaml`         | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/apps/technitium/technitium/app/persistent-volume-claim.yaml` | Persistent volume claim for DNS server configuration storage.              |
| `cluster/apps/technitium/technitium/app/certificate.yaml`             | Cert-manager Certificate for TLS termination.                              |
| `cluster/apps/technitium/technitium/app/pod-disruption-budget.yaml`   | Pod disruption budget ensuring availability during updates.                |
| `cluster/flux/meta/repositories/helm/bjw-s-labs-app-template.yaml`    | Helm repository definition pinning the upstream app-template source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage DNS services.
- Ensure the workstation can reach the Kubernetes API and that the `technitium` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Cert-manager must be deployed for TLS certificate management.
- Rook-ceph cluster storage must be available for persistent volumes.

## Operational Runbook

### Summary

Operate the Technitium DNS Server Helm release to provide reliable DNS resolution services, including secure DNS protocols and administrative API access, ensuring high availability and correct configuration for the spruyt-labs network.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when DNS changes could impact network resolution.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n technitium get helmrelease technitium -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/technitium/technitium/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr technitium --namespace technitium
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization technitium --with-source
   flux get kustomizations technitium -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease technitium -n technitium
   ```

#### Phase 3 – Monitor DNS Services

1. Verify DNS services are running and accessible:

   ```bash
   kubectl -n technitium get services
   kubectl -n technitium get pods
   ```

2. Test DNS resolution from within the cluster:

   ```bash
   kubectl run test-dns --image=busybox --rm -it -- nslookup google.com technitium.technitium.svc.cluster.local
   ```

3. Check API endpoints and secure protocols if configured.

#### Phase 4 – Manual Intervention for Service Issues

1. Restart pods if DNS queries fail:

   ```bash
   kubectl -n technitium rollout restart deployment technitium
   ```

2. Scale deployment for troubleshooting:

   ```bash
   kubectl -n technitium scale deployment technitium --replicas=0
   kubectl -n technitium scale deployment technitium --replicas=1
   ```

3. Inspect pod logs for configuration or runtime errors:

   ```bash
   kubectl -n technitium logs -l app.kubernetes.io/instance=technitium
   ```

4. Verify certificate validity and renewal:

   ```bash
   kubectl -n technitium get certificate
   kubectl -n technitium describe certificate dns-lan-${EXTERNAL_DOMAIN/./-}
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization technitium -n flux-system
   flux suspend helmrelease technitium -n technitium
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization technitium -n flux-system
   flux resume helmrelease technitium -n technitium
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n technitium scale deploy technitium --replicas=0
   ```

### Validation

- DNS queries resolve correctly from cluster pods and external clients.
- Services report healthy endpoints on ports 53 (TCP/UDP), 853 (DoT), 443 (DoH), 5380 (API HTTP), 53443 (API HTTPS).
- `flux get helmrelease technitium -n technitium` reports `Ready=True` with no pending upgrades.
- Certificate secrets are present and valid for TLS termination.
- Persistent volume claims are bound and accessible.

### Troubleshooting Guidance

- If DNS resolution fails, check pod readiness and liveness probes:

  ```bash
  kubectl -n technitium get pods -o wide
  kubectl -n technitium describe pod <pod-name>
  ```

- For secure protocol issues, verify TLS certificates and service configurations.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr technitium --namespace technitium
  kubeconform -strict -summary ./cluster/apps/technitium/technitium/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n technitium get pods
  kubectl -n technitium describe pod <pod-name>
  ```

- For external DNS issues, ensure LoadBalancer IP is assigned and reachable:

  ```bash
  kubectl -n technitium get svc technitium-dns
  ```

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                                                                           | Purpose                                                                                          |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                                                                | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                                                                            | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr technitium --namespace technitium`                                                               | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n technitium get events --sort-by=.lastTimestamp`                                                    | Confirms the deployment emits healthy events after rollout.                                      |
| `kubectl run test-dns --image=busybox --rm -it -- nslookup google.com technitium.technitium.svc.cluster.local` | Validates DNS resolution functionality.                                                          |
| `openssl s_client -connect <lb-ip>:853 -tls1_2`                                                                | Tests DNS over TLS connectivity.                                                                 |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../flux/README.md)
- Certificate management: [cluster/apps/README.md](../../README.md)
- Storage operations: [cluster/apps/README.md](../../README.md)
- Upstream Technitium DNS Server documentation: <https://technitium.com/dns/>
- Kubernetes DNS concepts: <https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/>
- DNS over TLS/HTTPS specifications: <https://tools.ietf.org/html/rfc7858>, <https://tools.ietf.org/html/rfc8484>
