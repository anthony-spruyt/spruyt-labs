# bedrock-connect Runbook

## Purpose and Scope

The bedrock-connect deployment provides a custom server list service for Minecraft Bedrock Edition clients. It allows players to see and connect to custom Minecraft servers through the featured servers list in the game client. This enables easy access to private or custom Minecraft servers without manual IP entry.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the bedrock-connect service healthy.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                              | Description                                                                |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/minecraft/README.md`                                | This runbook and component overview.                                       |
| `cluster/apps/minecraft/kustomization.yaml`                       | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/minecraft/namespace.yaml`                           | Namespace definition for the minecraft workload.                           |
| `cluster/apps/minecraft/bedrock-connect/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/minecraft/bedrock-connect/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/minecraft/bedrock-connect/app/release.yaml`         | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.          |
| `cluster/apps/minecraft/bedrock-connect/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/minecraft/bedrock-connect/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/bjw-s-labs-app-template.yaml`     | Helm repository definition pinning the upstream app-template source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage LoadBalancer services.
- Ensure the workstation can reach the Kubernetes API and that the `bedrock-connect` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Cilium LB IPAM must be configured for LoadBalancer IP assignment.

## Operational Runbook

### Summary

Operate the bedrock-connect Helm release to provide custom Minecraft server listings for Bedrock clients, ensuring players can easily connect to configured servers.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when server list updates could impact player connectivity.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n minecraft get helmrelease bedrock-connect -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/minecraft/bedrock-connect/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr bedrock-connect --namespace minecraft
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization bedrock-connect --with-source
   flux get kustomizations bedrock-connect -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease bedrock-connect -n minecraft
   ```

#### Phase 3 – Monitor Service Health

1. Watch deployment and service status:

   ```bash
   kubectl get pods -n minecraft -l app.kubernetes.io/name=bedrock-connect
   kubectl get svc -n minecraft bedrockconnect
   ```

2. Validate LoadBalancer IP assignment:

   ```bash
   kubectl get svc -n minecraft bedrockconnect -o wide
   ```

3. Check service events:

   ```bash
   kubectl get events -n minecraft --sort-by=.lastTimestamp
   ```

#### Phase 4 – Manual Intervention for Connectivity Issues

1. Inspect pod logs for startup or runtime errors:

   ```bash
   kubectl logs -n minecraft deploy/bedrock-connect
   ```

2. Verify custom servers configuration:

   ```bash
   kubectl get configmap -n minecraft bedrock-connect -o yaml
   ```

3. Test UDP connectivity to the service:

   ```bash
   nc -vuz <loadbalancer-ip> 19132
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization bedrock-connect -n flux-system
   flux suspend helmrelease bedrock-connect -n minecraft
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization bedrock-connect -n flux-system
   flux resume helmrelease bedrock-connect -n minecraft
   ```

4. Consider scaling the deployment to zero as a last resort:

   ```bash
   kubectl -n minecraft scale deploy/bedrock-connect --replicas=0
   ```

### Validation

- `kubectl get svc -n minecraft bedrockconnect` shows LoadBalancer with assigned external IP.
- `kubectl get pods -n minecraft -l app.kubernetes.io/name=bedrock-connect` reports Running pods.
- `flux get helmrelease bedrock-connect -n minecraft` reports `Ready=True` with no pending upgrades.
- Minecraft clients can see custom servers in featured servers list when connecting to the service.

### Troubleshooting Guidance

- If LoadBalancer IP is not assigned, check Cilium LB IPAM configuration and available IPs:

  ```bash
  kubectl get ciliumloadbalancerippools -A
  ```

- For connectivity issues, verify firewall rules and UDP port forwarding.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr bedrock-connect --namespace minecraft
  kubeconform -strict -summary ./cluster/apps/minecraft/bedrock-connect/app
  ```

- If pods crash, capture logs and describe the pod:

  ```bash
  kubectl -n minecraft get pods
  kubectl -n minecraft describe pod <pod-name>
  ```

- For configuration issues, validate the custom_servers.json format.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                       | Purpose                                                                                          |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `task validate`                                            | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                        | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr bedrock-connect --namespace minecraft`       | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n minecraft get events --sort-by=.lastTimestamp` | Confirms the service emits healthy events after rollout.                                         |
| `kubectl get svc -n minecraft bedrockconnect`              | Validates LoadBalancer service is properly configured.                                           |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../flux-system/flux-instance/README.md)
- Upstream app-template documentation: <https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common>
- BedrockConnect project: <https://github.com/Pugmatt/BedrockConnect>
- Custom image repository: <https://github.com/anthony-spruyt/bedrockconnect>
