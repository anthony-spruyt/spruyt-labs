# irq-balance-ms-01 Runbook

## Purpose and Scope

The irq-balance-ms-01 deployment runs the irqbalance daemon on specific nodes (ms-01-1, ms-01-2, ms-01-3) to distribute hardware interrupts across CPU cores, optimizing system performance and reducing latency. This configuration bans E-cores (8-15) to ensure interrupts are handled by P-cores for better performance.

Objectives:

- Describe the GitOps layout, deployment workflow, and operations required to keep the irqbalance daemon healthy on target nodes.
- Provide an operator-focused runbook for deployments, monitoring, and remediation.
- Capture validation, troubleshooting, and references that align with the repository runbook standards.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                                                                  | Description                                                                |
| --------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `cluster/apps/irq-balance/README.md`                                  | This runbook and component overview.                                       |
| `cluster/apps/irq-balance/kustomization.yaml`                         | Top-level Kustomize entry that namespaces resources and delegates to Flux. |
| `cluster/apps/irq-balance/namespace.yaml`                             | Namespace definition for the irq-balance workload.                         |
| `cluster/apps/irq-balance/irq-balance-ms-01/ks.yaml`                  | Flux `Kustomization` driving reconciliation of the HelmRelease overlay.    |
| `cluster/apps/irq-balance/irq-balance-ms-01/app/kustomization.yaml`   | Overlay combining the HelmRelease and generated values ConfigMap.          |
| `cluster/apps/irq-balance/irq-balance-ms-01/app/release.yaml`         | Flux `HelmRelease` referencing the bjw-s-labs app-template chart.          |
| `cluster/apps/irq-balance/irq-balance-ms-01/app/values.yaml`          | Rendered values supplied to the chart via ConfigMap.                       |
| `cluster/apps/irq-balance/irq-balance-ms-01/app/kustomizeconfig.yaml` | Remaps ConfigMap keys to Helm values for deterministic patches.            |
| `cluster/flux/meta/repositories/bjw-s-labs-app-template.yaml`         | Helm repository definition pinning the upstream app-template source.       |

<!-- markdownlint-enable MD013 -->

## Prerequisites

- Execute from the repository devcontainer or install `kubectl`, `flux`, `task`, and `age` locally with access to the Age key for secrets decryption.
- Possess write access to the Git repository and permission to manage daemonsets on target nodes.
- Ensure the workstation can reach the Kubernetes API and that the `irq-balance-ms-01` Flux objects are not suspended (`flux get kustomizations -n flux-system`).
- Target nodes (ms-01-1, ms-01-2, ms-01-3) must be schedulable and have appropriate labels.

## Operational Runbook

### Summary

Operate the irq-balance-ms-01 Helm release to run irqbalance daemons on designated nodes, ensuring interrupts are balanced across P-cores (banning E-cores 8-15) for optimal performance.

### Preconditions

- Confirm the repository working tree is clean and on the intended feature branch.
- Verify Flux controllers are healthy (`flux get kustomizations -n flux-system`, `flux get helmreleases -A`).
- Identify maintenance windows when irqbalance updates could impact node performance.
- Capture the current Helm release revision for rollback reference:

  ```bash
  kubectl -n irq-balance get helmrelease irq-balance-ms-01 -o yaml
  ```

### Procedure

#### Phase 1 – Plan and Author Changes

1. Update chart versions or values under `cluster/apps/irq-balance/irq-balance-ms-01/app/` as required.
2. Run `task validate` (invokes `kubeconform`, `yamllint`, and policy checks) to confirm schema compliance.
3. Execute targeted dry runs when touching Helm values:

   ```bash
   flux diff hr irq-balance-ms-01 --namespace irq-balance
   ```

4. Commit changes with runbook updates and open a pull request.

#### Phase 2 – Reconcile with Flux

1. After merge, monitor the Flux Kustomization:

   ```bash
   flux reconcile kustomization irq-balance-ms-01 --with-source
   flux get kustomizations irq-balance-ms-01 -n flux-system
   ```

2. Confirm the Helm release upgrade succeeded:

   ```bash
   flux get helmrelease irq-balance-ms-01 -n irq-balance
   ```

#### Phase 3 – Monitor DaemonSet Health

1. Watch daemonset pods on target nodes:

   ```bash
   kubectl get pods -n irq-balance -l app.kubernetes.io/name=irq-balance-ms-01
   kubectl describe ds irq-balance-ms-01 -n irq-balance
   ```

2. Validate events emitted by the daemonset:

   ```bash
   kubectl get events -n irq-balance --sort-by=.lastTimestamp
   ```

3. Ensure target nodes have the daemon running (`kubectl get nodes --show-labels`).

#### Phase 4 – Manual Intervention for Failed Pods

1. Check pod logs for startup failures:

   ```bash
   kubectl logs -n irq-balance ds/irq-balance-ms-01
   ```

2. Inspect node conditions if pods fail to schedule:

   ```bash
   kubectl describe node ms-01-1
   ```

3. Restart the daemonset if needed:

   ```bash
   kubectl rollout restart ds/irq-balance-ms-01 -n irq-balance
   ```

#### Phase 5 – Rollback or Disable

1. Revert the offending commit and push to `main`; Flux will reconcile the prior state.
2. Temporarily suspend reconciliation during investigations:

   ```bash
   flux suspend kustomization irq-balance-ms-01 -n flux-system
   flux suspend helmrelease irq-balance-ms-01 -n irq-balance
   ```

3. Resume once remediation is complete:

   ```bash
   flux resume kustomization irq-balance-ms-01 -n flux-system
   flux resume helmrelease irq-balance-ms-01 -n irq-balance
   ```

4. Consider scaling the daemonset to zero as a last resort:

   ```bash
   kubectl -n irq-balance patch ds/irq-balance-ms-01 --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/nodeSelector", "value": {"nonexistent": "true"}}]'
   ```

### Validation

- `kubectl get ds -n irq-balance` shows irq-balance-ms-01 with desired/ready pods matching target nodes.
- `kubectl get pods -n irq-balance -l app.kubernetes.io/name=irq-balance-ms-01` reports all pods Running.
- `flux get helmrelease irq-balance-ms-01 -n irq-balance` reports `Ready=True` with no pending upgrades.
- Interrupt distribution can be verified with `irqbalance --debug` on nodes (requires privileged access), ensuring E-cores are banned.

### Troubleshooting Guidance

- If pods fail to start, check privileged security context and host PID/IPC requirements:

  ```bash
  kubectl auth can-i use securitycontext --as system:serviceaccount:irq-balance:irq-balance-ms-01
  ```

- For scheduling failures, verify node selectors and tolerations match target nodes.
- When the Helm release fails to deploy, check rendered manifests:

  ```bash
  flux diff hr irq-balance-ms-01 --namespace irq-balance
  kubeconform -strict -summary ./cluster/apps/irq-balance/irq-balance-ms-01/app
  ```

- If pods crash, capture logs and describe the pod:

  ```bash
  kubectl -n irq-balance get pods
  kubectl -n irq-balance describe pod <pod-name>
  ```

- For performance issues, monitor interrupt distribution with system tools on target nodes, verifying E-core ban.

## Validation and Testing

<!-- markdownlint-disable MD013 -->

| Step                                                         | Purpose                                                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `task validate`                                              | Runs repository schema validation (kubeconform, yamllint, conftest) against component manifests. |
| `task dev-env:lint`                                          | Executes markdownlint, prettier, and ancillary linters to keep documentation compliant.          |
| `flux diff hr irq-balance-ms-01 --namespace irq-balance`     | Previews rendered Helm changes before reconciliation.                                            |
| `kubectl -n irq-balance get events --sort-by=.lastTimestamp` | Confirms the daemonset emits scheduling events after rollout.                                    |
| `kubectl get ds -n irq-balance`                              | Validates daemonset is running on target nodes.                                                  |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

- Runbook standards: [Repository root readme](../../../../README.md#runbook-standards)
- Flux control plane operations: [cluster/apps/flux-system/flux-instance/README.md](../../../../cluster/apps/flux-system/flux-instance/README.md)
- Upstream app-template documentation: <https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common>
- Upstream irqbalance documentation: <https://github.com/Irqbalance/irqbalance>
- Home Operations irqbalance image: <https://github.com/home-operations/containers/tree/main/apps/irqbalance>
- CPU core configuration reference: <https://gist.github.com/gavinmcfall/ea6cb1233d3a300e9f44caf65a32d519>
