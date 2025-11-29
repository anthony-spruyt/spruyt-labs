# cloudflared Runbook

## Purpose and Scope

The cloudflared deployment establishes a secure Cloudflare Tunnel to expose internal Kubernetes services to the public internet without requiring public IP addresses or opening inbound ports on the firewall. This runbook documents the GitOps layout, deployment workflow, and operations required to keep the tunnel healthy for the spruyt-labs environment.

Objectives:

- Describe where manifests and configuration live in this repository.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the root runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                  | Description                                                                    |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `cluster/apps/cloudflare-system/README.md`                            | This runbook and component overview.                                           |
| `cluster/apps/cloudflare-system/kustomization.yaml`                   | Top-level Kustomize entry that namespaces resources and delegates to Flux.     |
| `cluster/apps/cloudflare-system/namespace.yaml`                       | Namespace definition for the cloudflared workload.                             |
| `cluster/apps/cloudflare-system/cloudflared/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.        |
| `cluster/apps/cloudflare-system/cloudflared/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.              |
| `cluster/apps/cloudflare-system/cloudflared/app/release.yaml`         | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.              |
| `cluster/apps/cloudflare-system/cloudflared/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                           |
| `cluster/apps/cloudflare-system/cloudflared/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.                |
| `cluster/flux/meta/repositories/oci/bjw-s-labs-app-template.yaml`     | OCI repository definition pinning the upstream bjw-s-labs app-template source. |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage Cloudflare tunnels.
- Ensure the workstation can reach the Kubernetes API and that the `cloudflared` Flux objects are not suspended (`flux get kustomizations -n flux-system`).

## Operational Runbook

### Summary

Operate the cloudflared Helm release so internal services are securely exposed via Cloudflare Tunnel, keeping the tunnel authenticated and running without manual intervention.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when tunnel downtime could impact external access.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n cloudflare-system get helmrelease cloudflared -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/cloudflare-system/cloudflared/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr cloudflared --namespace cloudflare-system
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization cloudflared --with-source
   flux get kustomizations cloudflared -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease cloudflared -n cloudflare-system
   ```

#### Phase 3 – Monitor Tunnel Health

1. Watch tunnel status and connections:

   ```bash
   kubectl get pods -n cloudflare-system
   kubectl logs -n cloudflare-system deploy/cloudflared
   ```

2. Validate tunnel connectivity via Cloudflare dashboard or API.
3. Ensure services behind the tunnel are accessible.

#### Phase 4 – Manual Intervention for Tunnel Issues

1. Restart the deployment if connections fail:

   ```bash
   kubectl -n cloudflare-system rollout restart deploy/cloudflared
   ```

2. For token issues, verify the secret `cloudflared-secrets` contains the correct token.
3. Inspect logs for authentication or network errors:

   ```bash
   kubectl logs -n cloudflare-system deploy/cloudflared --previous
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization cloudflared -n flux-system
   flux suspend helmrelease cloudflared -n cloudflare-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization cloudflared -n flux-system
   flux resume helmrelease cloudflared -n cloudflare-system
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n cloudflare-system scale deploy/cloudflared --replicas=0
   ```

### Validation

- `kubectl get pods -n cloudflare-system` shows running pods with no restarts.
- `kubectl get helmrelease cloudflared -n cloudflare-system` reports `Ready=True` with no pending upgrades.
- Tunnel metrics at `/metrics` endpoint show active connections.
- External services are accessible via Cloudflare domains.

### Troubleshooting Guidance

- If tunnel fails to connect, check logs for "failed to connect" errors and verify network connectivity.
- For authentication failures, ensure the TUNNEL_TOKEN is valid and not expired.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr cloudflared --namespace cloudflare-system
  kubeconform -strict -summary ./cluster/apps/cloudflare-system/cloudflared/app
  ```

- If the deployment pod crashes, capture pod logs and describe the pod:

  ```bash
  kubectl -n cloudflare-system get pods
  kubectl -n cloudflare-system describe pod <pod-name>
  ```

- For Cloudflare API issues, consult Cloudflare dashboard for tunnel status.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                               | Purpose                                                                                          |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                    | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                                | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr cloudflared --namespace cloudflare-system`           | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n cloudflare-system get events --sort-by=.lastTimestamp` | Confirms the tunnel establishes connections after rollout.                                       |
| `kubectl get pods -n cloudflare-system`                            | Validates that the deployment is running and healthy.                                            |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](../../../flux/README.md)
- Certificate management: [cluster/apps/README.md](../../README.md)
- Upstream cloudflared documentation: <https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/>
- Cloudflare Tunnel documentation: <https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/tunnel-guide/>
