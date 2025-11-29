# minecraft-bedrock Runbook

## Purpose and Scope

The minecraft-bedrock deployment manages multiple Minecraft Bedrock Edition server instances in the cluster, including creative, survival, and better-on-bedrock variants. Each server provides a dedicated gaming environment with persistent storage and load-balanced access for players.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the Minecraft Bedrock servers healthy.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                          | Description                                                                |
| ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/minecraft/README.md`                            | This runbook and component overview.                                       |
| `cluster/apps/minecraft/kustomization.yaml`                   | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/minecraft/namespace.yaml`                       | Namespace definition for the minecraft workload.                           |
| `cluster/apps/minecraft/minecraft-bedrock/ks.yaml`            | Flux `Kustomization` managing multiple server instances.                   |
| `cluster/apps/minecraft/minecraft-bedrock/creative/`          | Creative mode server configuration.                                        |
| `cluster/apps/minecraft/minecraft-bedrock/survival/`          | Survival mode server configuration.                                        |
| `cluster/apps/minecraft/minecraft-bedrock/better-on-bedrock/` | Better-on-bedrock modded server configuration.                             |
| `cluster/flux/meta/repositories/minecraft-server-charts.yaml` | Helm repository definition for Minecraft server charts.                    |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage persistent volumes and LoadBalancer services.
- Ensure the workstation can reach the Kubernetes API and that the minecraft-bedrock Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Rook Ceph storage must be available for persistent volumes.
- Cilium LB IPAM must be configured for LoadBalancer IP assignment.

## Operational Runbook

### Summary

Operate the minecraft-bedrock Kustomizations to maintain multiple Minecraft Bedrock server instances, ensuring persistent worlds and reliable player access.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when server updates could impact player sessions.
- Capture the current Kustomization status for rollback reference:

  ```bash
  kubectl -n flux-system get kustomization minecraft-bedrock-creative -o yaml
  kubectl -n flux-system get kustomization minecraft-bedrock-survival -o yaml
  kubectl -n flux-system get kustomization minecraft-bedrock-better-on-bedrock -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update manifests under `cluster/apps/minecraft/minecraft-bedrock/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching manifests:

   ```bash
   flux diff ks minecraft-bedrock-creative --path=./cluster/apps/minecraft/minecraft-bedrock/creative
   flux diff ks minecraft-bedrock-survival --path=./cluster/apps/minecraft/minecraft-bedrock/survival
   flux diff ks minecraft-bedrock-better-on-bedrock --path=./cluster/apps/minecraft/minecraft-bedrock/better-on-bedrock
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomizations:

   ```bash
   flux reconcile kustomization minecraft-bedrock-creative --with-source
   flux reconcile kustomization minecraft-bedrock-survival --with-source
   flux reconcile kustomization minecraft-bedrock-better-on-bedrock --with-source
   flux get kustomizations -n flux-system -l app.kubernetes.io/name=minecraft-bedrock
   ```

2. Confirm the Helm releases are healthy:

   ```bash
   kubectl get helmrelease -n minecraft -l app.kubernetes.io/name=minecraft-bedrock
   ```

#### Phase 3 – Monitor Server Health

1. Watch server pods and services:

   ```bash
   kubectl get pods -n minecraft -l app.kubernetes.io/name=minecraft-bedrock
   kubectl get svc -n minecraft -l app.kubernetes.io/name=minecraft-bedrock
   ```

2. Validate LoadBalancer IP assignments:

   ```bash
   kubectl get svc -n minecraft -l app.kubernetes.io/name=minecraft-bedrock -o wide
   ```

3. Check server logs for startup and player activity:

   ```bash
   kubectl logs -n minecraft -l app.kubernetes.io/name=minecraft-bedrock --tail=50
   ```

#### Phase 4 – Manual Intervention for Server Issues

1. Inspect individual server logs for errors:

   ```bash
   kubectl logs -n minecraft deploy/minecraft-bedrock-creative
   kubectl logs -n minecraft deploy/minecraft-bedrock-survival
   kubectl logs -n minecraft deploy/minecraft-bedrock-better-on-bedrock
   ```

2. Check persistent volume claims for storage issues:

   ```bash
   kubectl get pvc -n minecraft -l app.kubernetes.io/name=minecraft-bedrock
   ```

3. Restart problematic servers:

   ```bash
   kubectl rollout restart deploy/minecraft-bedrock-<variant> -n minecraft
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization minecraft-bedrock-creative -n flux-system
   flux suspend kustomization minecraft-bedrock-survival -n flux-system
   flux suspend kustomization minecraft-bedrock-better-on-bedrock -n flux-system
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization minecraft-bedrock-creative -n flux-system
   flux resume kustomization minecraft-bedrock-survival -n flux-system
   flux resume kustomization minecraft-bedrock-better-on-bedrock -n flux-system
   ```

4. Consider scaling deployments to zero for maintenance:

   ```bash
   kubectl -n minecraft scale deploy/minecraft-bedrock-<variant> --replicas=0
   ```

### Validation

- `kubectl get svc -n minecraft -l app.kubernetes.io/name=minecraft-bedrock` shows LoadBalancers with assigned IPs.
- `kubectl get pods -n minecraft -l app.kubernetes.io/name=minecraft-bedrock` reports Running pods.
- `flux get kustomizations -n flux-system -l app.kubernetes.io/name=minecraft-bedrock` reports `Ready=True`.
- Minecraft clients can connect to servers using assigned IPs and ports.

### Troubleshooting Guidance

- If LoadBalancer IPs are not assigned, check Cilium LB IPAM and available IP pools:

  ```bash
  kubectl get ciliumloadbalancerippools -A
  ```

- For server startup failures, verify persistent volume binding and storage class:

  ```bash
  kubectl describe pvc -n minecraft <pvc-name>
  ```

- When manifests fail to apply, check for schema compliance:

  ```bash
  kubeconform -strict -summary ./cluster/apps/minecraft/minecraft-bedrock/
  ```

- If pods crash, capture logs and describe the pod:

  ```bash
  kubectl -n minecraft get pods
  kubectl -n minecraft describe pod <pod-name>
  ```

- For connectivity issues, verify firewall rules and UDP port exposure.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                                                                   | Purpose                                                                                          |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `task validate`                                                                                        | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                                                                    | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff ks minecraft-bedrock-<variant> --path=./cluster/apps/minecraft/minecraft-bedrock/<variant>` | Previews Kustomize changes before reconciliation.                                                |
| `kubectl -n minecraft get events --sort-by=.lastTimestamp`                                             | Confirms servers emit healthy events after rollout.                                              |
| `kubectl get svc -n minecraft -l app.kubernetes.io/name=minecraft-bedrock`                             | Validates LoadBalancer services are configured.                                                  |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](/README.md#runbook-standards)
- Flux control plane operations: [cluster/flux/README.md](/cluster/flux/README.md)
- Helm repository management: [cluster/flux/meta/repositories/README.md](/cluster/flux/meta/repositories/README.md)
- Minecraft server charts: <https://github.com/itzg/minecraft-server-charts>
- Minecraft Bedrock server Docker image: <https://hub.docker.com/r/itzg/minecraft-bedrock-server>
