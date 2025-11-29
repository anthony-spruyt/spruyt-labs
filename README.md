# spruyt-labs

Talos Linux home lab cluster managed with FluxCD-driven GitOps workflows.

## Purpose and Scope

This repository codifies the spruyt-labs baremetal environment, from Talos
machine configuration through workload deployment. It documents the operational
expectations for platform engineers, the tooling required to contribute
changes, and the runbooks necessary to recover common failure modes.

Objectives:

- Provide an auditable single source of truth for cluster and infrastructure
  state.
- Describe the workflows for preparing, reviewing, and shipping cluster
  changes.
- Cross-reference component-level runbooks and external documentation.

## Architecture Overview

- **Operating system** – Talos Linux 1.11 on Bossgame E2 control planes and
  Minisforum MS-01 workers. Talos image schematics and lifecycle procedures live
  in [`talos/README.md`](talos/README.md).
- **GitOps control plane** – FluxCD manages reconciliation for all Kubernetes
  resources defined under `cluster/`.
- **Networking** – Cilium supplies CNI, network policy, and BGP integrations for
  sensitive services.
- **Ingress** – Traefik handles internal ingress routing with Cloudflare tunnels
  (cloudflared) for remote access.
- **Storage** – Rook Ceph provides block, filesystem, and object storage with
  Velero handling backup and disaster recovery.
- **Caching** – Valkey provides Redis-compatible in-memory data storage.
- **Observability** – VictoriaMetrics pairs with Vector for log shipping.
  Dashboards are maintained in Grafana for monitoring cluster health.

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path                   | Description                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| `cluster/`             | Flux GitOps definitions for core, apps, CRDs, and machine overlays.                      |
| `cluster/apps/`        | Workload manifests grouped by namespace and Helm release overlays.                       |
| `cluster/flux/`        | Flux bootstrap resources, controllers, and repository definitions.                       |
| `infra/terraform/`     | Terraform workspaces for AWS backups, OIDC, and supporting cloud assets.                 |
| `talos/`               | Talos schematics, graceful shutdown steps, and upgrade guidance.                         |
| `talos/clusterconfig/` | Generated Talos machine configuration outputs (gitignored because they contain secrets). |
| `.taskfiles/`          | Taskfile automation for Talos, Flux, Terraform, and developer tooling.                   |
| `.devcontainer/`       | Development container bootstrap for a consistent CLI toolchain.                          |
| `Taskfile.yml`         | Root task index that aggregates the automation Taskfiles above.                          |

<!-- markdownlint-enable MD013 -->

## Operational Runbook

The following runbook governs day-to-day cluster changes. Component-specific
details must be added to the corresponding readme listed in the readme Index.

### Pre-Change Verification

Complete these verification steps before submitting changes to ensure cluster stability and prevent configuration drift.

#### Kubernetes Manifest Changes

- [ ] Confirm that the target resource type exists by running `kubectl api-resources` and recording the group/version you will touch.
- [ ] Review every field you intend to modify with `kubectl explain <resource_type>[.<field_path>]`, expanding child fields with `--recursive` when necessary.
- [ ] Retrieve and archive the current manifest with `kubectl get <resource_type> <resource_name> -n <namespace> -o yaml`, highlighting controller-managed sections you must not overwrite.
- [ ] Validate Helm chart defaults or CRD documentation through approved Context7 libraries or trusted upstream references, citing the material in your change notes.
- [ ] Capture assumptions, dependencies, and upstream version requirements so reviewers can confirm that automation and Talos state will reconcile cleanly.

#### Terraform Infrastructure Changes

1. `terraform fmt` and `terraform validate` within the `infra/terraform/` subdirectories you modify.
2. Run `terraform plan`, capture the output, and annotate any expected changes or surprises.
3. Request review with the plan output attached; ensure reviewers understand blast radius, dependencies, and roll-back strategy.
4. After approval, `terraform apply` with the exact plan you reviewed. Document the apply run in change notes or tickets.
5. Confirm state file synchronization (remote backend) and monitor downstream systems for drift.

#### Talos Configuration Changes

1. Use `talosctl health` and `talosctl logs -f kubelet` (as needed) to assess cluster health before upgrades or configuration changes.
2. Diff intended vs. live Talos machine config with `talosctl config diff` before applying updates.
3. Apply changes via `talosctl apply-config --insecure --nodes <target>` or Flux-managed Talos resources, avoiding partial application across control-plane nodes.
4. Verify post-change status with `talosctl health` and Kubernetes node readiness. Capture follow-up actions or anomalies.
5. Coordinate disruptive maintenance windows with platform owners listed in the escalation section.

### Cluster Change Workflow

1. **Prepare tooling** – Start from the devcontainer or run
   `task dev-env:install-age`, `task dev-env:install-flux`, and related install
   tasks to ensure CLI parity.
2. **Plan infrastructure updates** – Use Terraform tasks
   (`task terraform:init`, `task terraform:validate`, and `task terraform:fmt`)
   against `infra/terraform/` before editing Kubernetes state when cloud
   resources are impacted.
3. **Update Talos configuration as needed** – Regenerate configs with
   `task talos:gen` and apply to the appropriate node set via `task talos:apply`,
   `task talos:apply-c[1-3]`, or `task talos:apply-w[1-3]`.
4. **Author workload changes** – Modify manifests under `cluster/`, updating or
   creating component runbooks in the relevant readme.
5. **Document runbooks** – Capture Summary, Preconditions, Procedure,
   Validation, Troubleshooting, and Escalation details in the component readme
   during the same change.
6. **Validate locally** – Run `task dev-env:lint` to execute the mega-linter
   suite and address Markdown, YAML, and policy findings.
7. **Commit and push** – Use feature branches, include runbook context in commit
   messages, and open a PR for review.
8. **Flux reconciliation** – After merge, monitor reconciliation with
   `task flux:cap` (Flux Capacitor) or
   `flux reconcile kustomization <name> --with-source` to expedite rollout.
9. **Post-change validation** – Confirm workloads and infrastructure via the
   validation steps outlined below and update the changelog when appropriate.

### Day-0 and provisioning guidance

- For initial installs or Talos upgrades, reference the schematics and installer
  images documented in [`talos/README.md`](talos/README.md). SecureBoot ISO
  links are maintained there.
- Rotate secrets with `task talos:gen` and verify encrypted assets with SOPS
  before committing.
- Validate Talos installer selection via Factory (`factory.talos.dev/installer/...`), ensuring the SecureBoot schematic matches each node class before provisioning.
- Capture the fully-qualified installer digest and document the control plane endpoint IPs used for Talos upgrades.

### Day-2 operations

- Scale Talos workloads safely using the graceful shutdown pattern in
  [`talos/README.md`](talos/README.md), including Ceph flag management.
- Launch privileged pods for node diagnostics with
  `task dev-env:priv-pod node=<node>`.

### Renovate Dependency Management

#### Summary

Renovate automates dependency updates for Helm charts, Kubernetes manifests, Terraform configurations, and other components to keep the homelab infrastructure current and secure. Refer to [`.kilocode/rules/renovate.md`](.kilocode/rules/renovate.md) for detailed maintenance procedures.

#### Preconditions

- Renovate bot configured in GitHub repository settings with appropriate permissions.
- Configuration files present in `.github/renovate/` directory (helm.json5, groups.json5, regex-managers.json5, customManagers.json5).
- Repository structure matches configured file patterns for dependency detection.

#### Procedure by lifecycle phase

##### Configuration

1. Maintain Helm registry configurations in `.github/renovate/helm.json5` for chart repositories.
2. Update package groupings in `.github/renovate/groups.json5` to ensure related components (operators and CRDs, charts and images) update together.
3. Configure regex managers in `.github/renovate/regex-managers.json5` for custom dependency formats.
4. Adjust stability settings (stabilityDays) based on component criticality and update history.

##### Maintenance

1. Perform quarterly reviews of all Renovate configuration files to ensure they reflect current repository structure.
2. Monitor update success rates and system stability after dependency deployments.
3. Audit manager coverage to ensure all dependency types have appropriate configurations.
4. Update registries when URLs change or new repositories are introduced.

##### Updates

1. Renovate automatically detects dependencies and creates pull requests for updates.
2. Review PRs for compatibility, test changes in staging if available, and merge following cluster change workflow.
3. Monitor post-update stability and rollback if necessary.

#### Validation

- Check Renovate dashboard or GitHub PRs for active dependency update proposals.
- Verify updated dependency versions in manifests after merging PRs.
- Run `task dev-env:lint` to ensure no linting issues introduced by updates.
- Confirm cluster stability with `kubectl get nodes` and `flux get kustomizations -n flux-system`.

#### Troubleshooting

- **Failed updates**: Review PR comments for errors; adjust stabilityDays or groupings if updates are too frequent or unstable.
- **Missing dependencies**: Audit manager configurations and file patterns; add new managers for undetected dependency types.
- **Stability issues**: Roll back problematic updates by reverting commits or suspending HelmReleases; increase stabilityDays for critical components.
- **Configuration errors**: Validate JSON5 syntax in configuration files; test with Renovate dry-run locally.

#### Escalation

- Contact platform operations for configuration issues, failed updates impacting production, or when automated updates require manual intervention.
- Escalate to documentation governance for updates to the Renovate rule or configuration standards.

## Runbook Standards

Each component readme must adopt the following structure to remain consistent
and actionable:

1. **Summary** – One to two sentences describing the service and primary
   objective of the runbook.
2. **Preconditions** – Required context such as cluster state, credentials, and
   maintenance windows.
3. **Procedure by lifecycle phase** – Break instructions into phases (for
   example _Plan_, _Apply_, _Validate_, _Rollback_) and enumerate steps in
   order.
4. **Validation** – Explicit checks that verify success (kubectl commands,
   Talos health checks, service endpoints).
5. **Troubleshooting** – Known failure signatures with diagnostic commands and
   remediation guidance.
6. **Escalation** – Next contacts, tooling escalations, or external references
   for unresolved incidents.

## Validation and Testing

- `task dev-env:lint` – Runs mega-linter (markdownlint, textlint, prettier)
  across the repository.
- `task terraform:fmt` and `task terraform:validate` – Keep Terraform
  workspaces consistent before plan or apply stages.
- `task talos:apply-*` – Apply regenerated Talos configuration; verify Talos
  health with `talosctl health`.
- `kubectl get kustomizations -n flux-system` – Confirm Flux objects reconcile
  successfully after a push.
- `flux reconcile kustomization <name> --with-source` – Force and observe
  reconciliation during emergency fixes.
- `task dev-env:install-helm-plugins` – Keep helm-diff and schema generation
  plugins current for chart updates.

## Troubleshooting Matrix

This consolidated matrix covers common failure modes across the cluster, applications, and infrastructure. For component-specific issues, reference the app READMEs which may link here.

<!-- markdownlint-disable MD013 -->

| Failure Mode/Symptom                              | Diagnostics/Actions                                                                                                                                                                                                                                                                                                                                                 | Remediation                                                                                                    |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Flux reconciliation failures                      | Inspect reconciliation state with `kubectl get kustomizations -n flux-system` and `kubectl describe kustomization <name> -n flux-system`. Trigger manual reconciliation using `flux reconcile kustomization <name> --with-source`. Launch Flux Capacitor via `task flux:cap` for GUI-assisted diffing. Validate repository sync and reinstall Flux CLI if outdated. | Resolve Git authentication, SOPS decryption, or repository dependency issues, then trigger `flux reconcile`.   |
| Talos upgrade pitfalls                            | Drain workload nodes and place Ceph into maintenance mode. Monitor logs for regressions. Gather diagnostics via `talosctl dmesg` and `talosctl logs -k`. Confirm SecureBoot schematic. Run post-upgrade verification checks.                                                                                                                                        | Reapply prior configuration if issues appear. Ensure correct factory images and SecureBoot settings.           |
| Rook Ceph storage health issues                   | Access toolbox with `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools --bash`. Investigate crashes with `ceph crash ls` and `ceph crash archive-all`. Retrieve dashboard credentials. Free or modify PVs as needed.                                                                                                                                             | Archive crashes, check cluster health, and manage OSD maintenance modes.                                       |
| Container runtime or node crashes                 | Use `talosctl logs containerd`, `talosctl logs cri`, and `talosctl logs etcd`. Launch privileged pod for inspection.                                                                                                                                                                                                                                                | Investigate kernel or runtime problems, check for regressions.                                                 |
| Helm chart rendering errors                       | `flux logs --kind HelmRelease --name <app> -n <namespace>`, `helm template` locally                                                                                                                                                                                                                                                                                 | Correct values syntax, adjust chart versions, or align schema with upstream documentation.                     |
| Schema mismatches (kubeconform errors, CRD drift) | `kubeconform --summary`, `kubectl describe crd <resource>`                                                                                                                                                                                                                                                                                                          | Update CRDs under `resources/`, rerun kubeconform, ensure Flux applies CRD updates before HelmRelease changes. |
| Application unhealthy post-upgrade                | `kubectl get events -n <namespace>`, workload logs, service endpoints                                                                                                                                                                                                                                                                                               | Revert commit, suspend HelmRelease, or rollback image tag/values. Validate dependent services.                 |
| Secret or config drift                            | `kubectl get secret <name> -n <namespace> -o yaml`, `task sops:decrypt`                                                                                                                                                                                                                                                                                             | Regenerate secrets, re-encrypt with SOPS, commit updates, ensure external secret stores refreshed.             |
| CSRs stuck in `Pending`                           | Check controller logs, validate RBAC, confirm Talos nodes advertise expected SANs.                                                                                                                                                                                                                                                                                  | Approve manually only after investigation. Ensure proper RBAC and node identity.                               |
| Permission denied errors                          | Ensure service account retains required verbs; reconcile Flux Kustomization.                                                                                                                                                                                                                                                                                        | Reapply RBAC if drift detected.                                                                                |
| Controller pod `CrashLoopBackOff`                 | Describe pod, inspect logs, verify ConfigMap values.                                                                                                                                                                                                                                                                                                                | Roll back to prior release if misconfiguration found.                                                          |
| Nodes never join after approval                   | Inspect `talosctl logs kubelet`, confirm CSR includes `system:nodes` group.                                                                                                                                                                                                                                                                                         | Ensure issued certificate subject matches node name.                                                           |
| Helm chart schema lookups                         | Search GitHub with regex `/yaml-language-server:\s*[^\n]*appkeyword[^\n]*\.json/`                                                                                                                                                                                                                                                                                   | Locate appropriate YAML language server schemas for chart values.                                              |

<!-- markdownlint-enable MD013 -->

## References and Cross-links

### Documentation Index

<!-- markdownlint-disable MD013 -->

#### Operational Runbooks

| Component/Service    | Readme                                                                                       |
| -------------------- | -------------------------------------------------------------------------------------------- |
| Cluster applications | [`cluster/apps/README.md`](cluster/apps/README.md)                                           |
| CSR automation       | [`cluster/apps/kubelet-csr-approver/README.md`](cluster/apps/kubelet-csr-approver/README.md) |
| Custom resources     | [`cluster/crds/README.md`](cluster/crds/README.md)                                           |
| Flux bootstrap       | [`cluster/flux/README.md`](cluster/flux/README.md)                                           |

#### Infrastructure and Lifecycle

| Area                              | Readme                                                               |
| --------------------------------- | -------------------------------------------------------------------- |
| Talos lifecycle overview          | [`talos/README.md`](talos/README.md)                                 |
| Talos machine lifecycle deep dive | [`talos/docs/machine-lifecycle.md`](talos/docs/machine-lifecycle.md) |
| Infrastructure                    | [`infra/README.md`](infra/README.md)                                 |

#### Rules and Procedures

| Document                         | Description                                                                                |
| -------------------------------- | ------------------------------------------------------------------------------------------ |
| Kubernetes workflow guidelines   | [`.kilocode/rules/kubernetes.md`](.kilocode/rules/kubernetes.md)                           |
| Project context and guidelines   | [`.kilocode/rules/project_context.md`](.kilocode/rules/project_context.md)                 |
| Shared procedures                | [`.kilocode/rules/shared-procedures.md`](.kilocode/rules/shared-procedures.md)             |
| Context7 library usage           | [`.kilocode/rules/user_context7_libraries.md`](.kilocode/rules/user_context7_libraries.md) |
| Renovate configuration standards | [`.kilocode/rules/renovate.md`](.kilocode/rules/renovate.md)                               |

#### Templates

| Template        | Purpose                                                          |
| --------------- | ---------------------------------------------------------------- |
| README template | [`.kilocode/templates/README.md`](.kilocode/templates/README.md) |

<!-- markdownlint-enable MD013 -->

> Ensure component READMEs exist and follow the Runbook Standards defined
> above.

### Component documentation

- [Talos Linux documentation](https://www.talos.dev/) — Configuration reference
  and upgrade guides.
- [Talhelper](https://github.com/budimanjojo/talhelper) — CLI automation for
  Talos configuration generation.
- [FluxCD](https://fluxcd.io/) — GitOps controller reference and troubleshooting.
- [Cilium](https://github.com/cilium/cilium) and its
  [Helm reference](https://docs.cilium.io/en/stable/helm-reference/) — CNI
  policy and BGP configuration guidance.
- [Traefik documentation](https://doc.traefik.io/) — Ingress routing and
  certificate management.
- [Rook Ceph](https://github.com/rook/rook) — Storage operator documentation and
  [encryption guidance](https://rook.io/docs/rook/latest/Storage-Configuration/Ceph-CSI/ceph-csi-drivers/#enable-rbd-and-cephfs-encryption-support).
- [Velero](https://velero.io/) and the
  [AWS plugin](https://github.com/vmware-tanzu/velero-plugin-for-aws) —
  Backup and restore workflows.
- [Cloudflared](https://github.com/cloudflare/cloudflared) — Secure tunneling
  for ingress.
- [Cert-Manager](https://cert-manager.io/) — ACME issuers and certificate
  lifecycle.
- [VictoriaMetrics](https://docs.victoriametrics.com/) and
  [Vector](https://vector.dev/docs/) — Observability stack.
- [Mosquitto authentication methods](https://mosquitto.org/documentation/authentication-methods/)
  — MQTT user management.
- [CloudNativePG documentation](https://cloudnative-pg.io/documentation/1.27/)
  — PostgreSQL operator tuning.
- [Valkey](https://valkey.io/) — In-memory data structure store.

### Tooling and automation

- `task` orchestrates repeatable workflows defined in `.taskfiles/`.
- Use Context7 MCP ([GitHub](https://github.com/upstash/context7),
  [Dashboard](https://context7.com/dashboard)) for authoritative upstream
  documentation retrieval.
- The devcontainer image supplies TalosCTL, kubectl, Flux, Helm, Terraform,
  SOPS, and supporting CLIs.
- Mega-linter pipelines (`task dev-env:lint`) enforce a plethora of linters and scanning tools such prettier,
  trivy, and other checks.

## Escalation and Ownership

### Platform Operations

- **Cluster operations:** _Owner TBD_ — add contact (Slack channel, email, or on-call rotation). Dependency: platform team to provide canonical contact list.
- **Talos lifecycle management:** _Owner TBD_ — coordinate disruptive maintenance windows and image changes.

### Infrastructure and Cloud Resources

- **Terraform infrastructure:** _Owner TBD_ — specify responsible maintainer or triage channel for AWS/Terraform changes.

### Documentation and Tooling

- **Documentation governance:** _Owner TBD_ — identify who approves rule updates and maintains MCP catalog entries.

### General Escalation Guidelines

Operational questions and incidents should be tracked via repository issues or the internal on-call channel. Include runbook references, recent Flux reconcile outputs, and Talos log excerpts in any escalation. Update the placeholders above once maintainers publish the official contact matrix. Until then, flag ownership gaps in pull requests.

## Agent-Friendly Workflows

This section provides decision trees and conditional logic for autonomous execution of cluster management tasks, including deployment verification and troubleshooting escalation.

### Cluster Health Verification Workflow

```bash
If kubectl get nodes --no-headers | grep -v Ready > /dev/null
Then:
  Run talosctl health
  Expected output: All nodes report healthy
  If health check fails:
    Run talosctl logs -f kubelet
    Expected output: No critical errors in logs
    Recovery: Reapply Talos configuration with task talos:apply
  Else:
    Proceed to Flux reconciliation check
Else:
  Proceed to Flux reconciliation check
```

### Flux Reconciliation Monitoring Workflow

```bash
If flux get kustomizations -n flux-system --no-headers | grep -v "True" > /dev/null
Then:
  For each failing kustomization:
    Run flux reconcile kustomization <name> --with-source
    Expected output: Reconciliation completes without errors
    If reconciliation fails:
      Run flux logs --kind Kustomization --name <name> -n flux-system
      Expected output: Identify root cause (e.g., Git auth, SOPS decryption)
      Recovery: Resolve dependencies and rerun reconcile; escalate if persistent
  Else:
    Proceed to application health checks
Else:
  Proceed to application health checks
```

### Troubleshooting Escalation Workflow

```bash
If application health checks fail (kubectl get pods -A --no-headers | grep -v Running > /dev/null)
Then:
  Run kubectl get events -A --sort-by=.lastTimestamp | tail -20
  Expected output: Recent events indicate issue type
  If events show resource constraints:
    Run kubectl describe pod <pod-name> -n <namespace>
    Expected output: Resource limits exceeded
    Recovery: Adjust resource requests/limits in manifests
  Else if events show image pull failures:
    Run kubectl describe pod <pod-name> -n <namespace>
    Expected output: Image pull error details
    Recovery: Verify image registry access and credentials
  Else:
    Escalate to platform operations with logs and events
Else:
  Cluster deployment verified successfully
```
