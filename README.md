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

- **Operating system** – Talos Linux 1.11 on control plane and worker nodes.
  Talos image schematics and lifecycle procedures live in [`talos/README.md`](talos/README.md).
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

- [ ] Confirm that the target resource type exists by running

```bash
kubectl api-resources
```

and recording the group/version you will touch.

- [ ] Review every field you intend to modify with

```bash
kubectl explain <resource_type>[.<field_path>] --recursive
```

when necessary.

- [ ] Retrieve and archive the current manifest with

```bash
kubectl get <resource_type> <resource_name> -n <namespace> -o yaml
```

highlighting controller-managed sections you must not overwrite.

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

### Development Environment Setup

#### Devcontainer Configuration

The repository includes a comprehensive devcontainer configuration (`.devcontainer/`) that provides a consistent development environment with all required tools pre-installed.

**Features included:**

- Ubuntu base image with essential development tools
- Docker-in-Docker support for local testing
- Kubernetes tools: kubectl, helm, kustomize
- Infrastructure tools: Terraform, Ansible
- GitOps tools: Flux CLI, Talos CLI, Talhelper
- CI/CD tools: Renovate CLI, pre-commit hooks
- Language support: Node.js, Python, Go
- VS Code extensions for Kubernetes, YAML, Terraform development

**Setup procedure:**

1. Open the repository in VS Code
2. When prompted, click "Reopen in Container" or use Command Palette: "Dev Containers: Reopen in Container"
3. Wait for the post-create script to complete (installs additional tools)
4. Verify installation with `task --list` to see available tasks

**Local testing capabilities:**

- Run `task dev-env:lint` for comprehensive code quality checks
- Use `task terraform:validate` for infrastructure validation
- Execute `task talos:gen` for configuration generation testing
- Access Flux Capacitor at `http://localhost:3333` for GitOps visualization

#### Taskfile Automation

The repository uses Task (a Make alternative) for workflow automation. Key development tasks:

**Environment setup:**

- `task dev-env:install-age` - Install Age encryption tool
- `task dev-env:install-flux` - Install Flux CLI
- `task dev-env:install-talosctl` - Install Talos CLI
- `task dev-env:install-talhelper` - Install Talhelper for config generation

**Validation and testing:**

- `task dev-env:lint` - Run mega-linter suite (markdownlint, yamllint, etc.)
- `task terraform:fmt` - Format Terraform files
- `task terraform:validate` - Validate Terraform configurations

**Local development workflow:**

- `task talos:gen` - Generate Talos machine configurations
- `task flux:cap` - Launch Flux Capacitor for reconciliation monitoring
- `task sops:decrypt` - Decrypt secrets for local development

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
   validation steps outlined below.

### Cluster Bootstrap and Initial Deployment

This section provides comprehensive guidance for initial cluster deployment, including hardware requirements, network setup, and step-by-step provisioning procedures.

#### Hardware Requirements

| Component | Control Plane (Bossgame E2) | Workers (MS-01) |
| --------- | --------------------------- | --------------- |
| CPU       | 4+ cores, 8+ threads        | 4+ cores        |
| Memory    | 16GB min, 32GB recommended  | 16GB min        |
| Storage   | 256GB NVMe + Ceph OSDs      | 256GB NVMe      |
| Network   | 1GbE min, 2.5GbE preferred  | 1GbE min        |

**Network Infrastructure**: Router with BGP/VLANs, managed switch, separate VLANs for management (10.10.0.0/24), storage (10.10.10.0/24), services (10.10.20.0/24).

#### Network Setup

1. **Configure VLANs**:

   ```bash
   # Management VLAN (10.10.0.0/24)
   # Storage VLAN (10.10.10.0/24)
   # Services VLAN (10.10.20.0/24)
   ```

2. **Set up DHCP reservations** for cluster nodes:

   - Control plane: 10.10.0.11, 10.10.0.12, 10.10.0.13
   - Workers: 10.10.0.21, 10.10.0.22, 10.10.0.23

3. **Configure BGP** on router for Cilium integration:

   - AS number: 64512 (private)
   - Neighbor: Cluster VIP (10.10.0.10)
   - Advertise service subnets

4. **DNS configuration**:
   - Internal domain: spruyt-labs.lan
   - External domain: spruyt-labs.com
   - Wildcard records for ingress

#### Bootstrap Procedure

##### Phase 1: Repository and Tooling Setup

1. **Clone repository** and enter devcontainer:

   ```bash
   git clone https://github.com/your-org/spruyt-labs.git
   cd spruyt-labs
   # Open in VS Code with devcontainer
   ```

2. **Install required tooling**:

   ```bash
   task dev-env:install-age
   task dev-env:install-flux
   task dev-env:install-talos
   ```

3. **Decrypt secrets** (requires Age identity):
   ```bash
   # Ensure AGE_IDENTITY environment variable is set
   task sops:decrypt
   ```

##### Phase 2: Infrastructure Preparation

1. **Bootstrap Terraform Cloud workspaces**:

   ```bash
   cd infra/terraform/workspace-factory
   terraform init
   terraform plan -out plan.tfplan
   terraform apply plan.tfplan
   ```

2. **Configure Terraform variable sets** in Terraform Cloud for each workspace

3. **Provision AWS infrastructure** (if using cloud backups):
   ```bash
   cd infra/terraform/aws/velero-backup
   terraform init
   terraform plan -out plan.tfplan
   terraform apply plan.tfplan
   ```

##### Phase 3: Talos Configuration Generation

1. **Update talconfig.yaml** with node specifications:

   ```yaml
   clusterName: spruyt-labs
   endpoint: https://10.10.0.10:6443
   nodes:
     - hostname: bossgame-e2-01
       ipAddress: 10.10.0.11
       controlPlane: true
       schematic: 7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6
   ```

2. **Generate Talos secrets**:

   ```bash
   task talos:gen
   ```

3. **Generate machine configurations**:
   ```bash
   talhelper genconfig
   ```

##### Phase 4: Node Provisioning

1. **Download Talos installer ISOs**:

   - Control plane: [SecureBoot ISO](https://factory.talos.dev/image/7545fb734ed1aedc102a971aa833ae3927c260bd6cc70744469001bee8f8e1b6/v1.11.5/metal-amd64-secureboot.iso)
   - Worker: [SecureBoot ISO](https://factory.talos.dev/image/7d51373a99be01395b499f21e0cdf3d27cca57c3feab356c20efe96a2df341bf/v1.11.5/metal-amd64-secureboot.iso)

2. **Boot first control plane node** with Talos ISO

3. **Apply configuration**:

   ```bash
   talosctl apply-config --insecure --nodes 10.10.0.11 \
     --file talos/clusterconfig/bossgame-e2-01.yaml
   ```

4. **Bootstrap Kubernetes**:

   ```bash
   talosctl bootstrap --nodes 10.10.0.11
   ```

5. **Verify cluster**:

   ```bash
   talosctl health --nodes 10.10.0.11
   kubectl get nodes
   ```

6. **Repeat for remaining nodes** (control plane first, then workers)

##### Phase 5: Flux Bootstrap

1. **Install Flux CLI** and bootstrap:

   ```bash
   flux bootstrap github \
     --owner=your-org \
     --repository=spruyt-labs \
     --branch=main \
     --path=cluster/flux \
     --personal
   ```

2. **Monitor bootstrap**:

   ```bash
   flux get kustomizations -n flux-system
   ```

3. **Verify cluster components**:
   ```bash
   kubectl get pods -A
   ```

##### Phase 6: Post-Bootstrap Configuration

1. **Configure external DNS** for ingress domains

2. **Set up certificate management** with cert-manager

3. **Deploy monitoring stack** (VictoriaMetrics, Vector, Grafana)

4. **Configure backup solutions** (Velero, CNPG backups)

5. **Test cluster functionality**:
   - Deploy test application
   - Verify ingress and TLS
   - Test storage provisioning
   - Validate monitoring and alerting

#### Validation Checklist

- [ ] All nodes report Ready status
- [ ] Flux kustomizations are reconciled
- [ ] Core services (Cilium, cert-manager, external-dns) are running
- [ ] Ingress controller accessible
- [ ] Storage classes available
- [ ] Monitoring dashboards accessible
- [ ] Backup jobs scheduled

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

## Cluster Monitoring and Alerting

### Monitoring Stack Overview

The spruyt-labs cluster uses VictoriaMetrics as the primary monitoring and alerting platform, providing comprehensive observability for infrastructure and applications.

**Components:**

- **VictoriaMetrics k8s-stack**: Metrics collection, storage, and alerting (Prometheus-compatible)
- **VictoriaMetrics Operator**: Manages VictoriaMetrics resources and configurations
- **Victoria Logs Single**: Centralized log aggregation and analysis
- **VictoriaMetrics Secret Writer**: Automated secret management for monitoring components
- **Grafana**: Visualization and dashboarding for metrics and logs

### Basic Monitoring Commands

**Cluster health:**

```bash
# Check overall cluster status
kubectl get nodes
kubectl get pods -A --no-headers | grep -v Running

# Monitor resource usage
kubectl top nodes
kubectl top pods -A
```

**Flux reconciliation:**

```bash
# Check Flux kustomization status
flux get kustomizations -A

# Monitor specific kustomization
flux get kustomizations -n flux-system
```

**VictoriaMetrics health:**

```bash
# Check VictoriaMetrics pods
kubectl get pods -n observability -l app.kubernetes.io/name=victoria-metrics-k8s-stack

# Verify metrics ingestion
kubectl exec -n observability <victoria-metrics-pod> -- curl -s http://localhost:8428/api/v1/query?query=up
```

### Troubleshooting Monitoring

| Issue                | Diagnostic Commands                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------- |
| Metrics missing      | `kubectl get servicemonitors -A`, check VictoriaMetrics targets                                    |
| Logs not aggregating | `kubectl exec -n observability <victoria-logs-pod> -- curl -s http://localhost:9428/api/v1/status` |
| Alerts not firing    | `kubectl logs -n observability -l app.kubernetes.io/name=victoria-metrics-k8s-stack-alertmanager`  |
| Storage issues       | `kubectl get pvc -A`, `kubectl exec -n rook-ceph <rook-tools-pod> -- ceph df`                      |

### Grafana Access

Access via ingress: `kubectl get ingress -n observability -l app.kubernetes.io/name=grafana`

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

| Component/Service    | Readme                                                                                                                                 |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | --- |
| Cluster applications | [`cluster/apps/README.md`](cluster/apps/README.md)                                                                                     |
| CSR automation       | [`cluster/apps/kubelet-csr-approver/kubelet-csr-approver/README.md`](cluster/apps/kubelet-csr-approver/kubelet-csr-approver/README.md) |     |
| Flux bootstrap       | [`cluster/flux/README.md`](cluster/flux/README.md)                                                                                     |

#### Infrastructure and Lifecycle

| Area                              | Readme                                                               |
| --------------------------------- | -------------------------------------------------------------------- |
| Talos lifecycle overview          | [`talos/README.md`](talos/README.md)                                 |
| Talos machine lifecycle deep dive | [`talos/docs/machine-lifecycle.md`](talos/docs/machine-lifecycle.md) |
| Infrastructure                    | [`infra/README.md`](infra/README.md)                                 |

#### Rules and Procedures

| Document                         | Description                                                      |
| -------------------------------- | ---------------------------------------------------------------- |
| Kubernetes workflow guidelines   | [`.kilocode/rules/core_rules.md`](.kilocode/rules/core_rules.md) |
| Project context and guidelines   | [`.kilocode/rules/core_rules.md`](.kilocode/rules/core_rules.md) |
| Shared procedures                | [`.kilocode/rules/procedures.md`](.kilocode/rules/procedures.md) |
| Context7 library usage           | [`.kilocode/rules/procedures.md`](.kilocode/rules/procedures.md) |
| Renovate configuration standards | [`.kilocode/rules/renovate.md`](.kilocode/rules/renovate.md)     |

#### Templates

| Template        | Purpose                                                                            |
| --------------- | ---------------------------------------------------------------------------------- |
| README template | [`.kilocode/templates/readme_template.md`](.kilocode/templates/readme_template.md) |

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
- [VictoriaMetrics Operator](https://docs.victoriametrics.com/operator/) — Kubernetes operator documentation.
- [Mosquitto authentication methods](https://mosquitto.org/documentation/authentication-methods/)
  — MQTT user management.
- [CloudNativePG documentation](https://cloudnative-pg.io/docs/)
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

## Quick Verification Commands

```bash
# Cluster health
kubectl get nodes
talosctl health

# Flux status
flux get kustomizations -n flux-system

# Unhealthy pods
kubectl get pods -A --no-headers | grep -v Running

# Recent events
kubectl get events -A --sort-by=.lastTimestamp | tail -20
```
