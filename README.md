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
  Raspberry Pi 4 workers. Talos image schematics and lifecycle procedures live
  in [`talos/README.md`](talos/README.md).
- **GitOps control plane** – FluxCD manages reconciliation for all Kubernetes
  resources defined under `cluster/`.
- **Networking** – Cilium supplies CNI, network policy, and BGP integrations for
  sensitive services.
- **Ingress** – Traefik handles internal ingress routing with Cloudflare tunnels
  (cloudflared) for remote access.
- **Storage** – Rook Ceph provides block, filesystem, and object storage with
  Velero handling backup and disaster recovery.
- **Observability** – VictoriaMetrics pairs with Vector for log shipping.
  Dashboards will be committed once finalized.

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
6. **Validate locally** – Run `task dev-env:lint` to execute the super-linter
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
- Maintain Rook Ceph dashboards via Grafana (dashboard `2842`) and commit any
  dashboard JSON once sourced.
- Validate Talos installer selection via Factory (`factory.talos.dev/installer/...`), ensuring the SecureBoot schematic matches each node class before provisioning.
- Capture the fully-qualified installer digest and document the control plane endpoint IPs used for Talos upgrades.

### Day-2 operations

- Scale Talos workloads safely using the graceful shutdown pattern in
  [`talos/README.md`](talos/README.md), including Ceph flag management.
- Launch privileged pods for node diagnostics with
  `task dev-env:priv-pod node=<node>`.

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

- `task dev-env:lint` – Runs super-linter (markdownlint, textlint, prettier)
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

## Troubleshooting

### Flux reconciliation failures

- Inspect reconciliation state with
  `kubectl get kustomizations -n flux-system` and
  `kubectl describe kustomization <name> -n flux-system`.
- Trigger manual reconciliation using
  `flux reconcile kustomization <name> --with-source`.
- Launch Flux Capacitor via `task flux:cap` for GUI-assisted diffing; ensure the
  devcontainer has GUI forwarding enabled.
- Validate repository sync (Helm repositories under
  `cluster/flux/meta/repositories/`) and reinstall the Flux CLI with
  `task dev-env:install-flux` if your binary is outdated.

### Talos upgrade pitfalls

- Drain workload nodes and place Ceph into maintenance mode (`ceph osd set
noout`, etc.) as documented in [`talos/README.md`](talos/README.md).
- Upgrade nodes using the factory images listed in `talos/README.md` and verify
  versions with `talosctl version -n <node>`.
- Monitor `talosctl -n <node> logs etcd` and `talosctl -n <node> logs
containerd` for regressions. Reapply prior configuration with
  `task talos:apply-<node>` if issues appear.
- Gather diagnostics via `talosctl -n <node> dmesg` and
  `talosctl -n <node> logs -k` for kernel or runtime problems.
- Skipping SecureBoot validation: Always confirm the Factory installer link uses the correct `secureboot` schematic (`secureboot:1` vs `secureboot:0`) prior to upgrades.
- Incomplete verification: After `talosctl upgrade`, run `talosctl version`, `kubectl get nodes`, `flux get kustomizations`, and check etcd health to catch drift early; see `talos/docs/machine-lifecycle.md` for the full checklist.

### Rook Ceph storage health

- Access the toolbox using
  `kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash`.
- Investigate and archive crashes:

  ```bash
  ceph crash ls
  ceph crash archive-all
  ```

- Retrieve dashboard credentials:

  ```bash
  kubectl -n rook-ceph get secret rook-ceph-dashboard-password \
    -o jsonpath="{['data']['password']}" | base64 --decode && echo
  ```

- Free or modify persistent volumes:

  ```bash
  kubectl patch pv <PVC_NAME> --type=json \
    -p='[{"op": "remove", "path": "/spec/claimRef"}]'

  kubectl patch pv <PVC_NAME> --type=json \
    -p='[{"op": "replace", "path": "/spec/accessModes", "value": ["ReadWriteOnce"]}]'
  ```

### Container runtime or node crashes

- Use `talosctl -n <node> logs containerd`, `talosctl -n <node> logs cri`, and
  `talosctl -n <node> logs etcd` for targeted diagnostics.
- Launch a privileged pod (`task dev-env:priv-pod node=<node>`) for quick
  filesystem or network inspection.

### Helm chart schema lookups

- Locate YAML language server schemas for chart values by searching GitHub with
  the regular expression `/yaml-language-server:\s*[^\n]*appkeyword[^\n]*\.json/`.

## References and Cross-links

### Readme Index

<!-- markdownlint-disable MD013 -->

| Area                              | Readme                                                                                  |
| --------------------------------- | --------------------------------------------------------------------------------------- |
| Cluster applications              | [`cluster/apps/README.md`](cluster/apps/README.md)                                      |
| Custom resources                  | [`cluster/crds/README.md`](cluster/crds/README.md)                                      |
| Flux bootstrap                    | [`cluster/flux/README.md`](cluster/flux/README.md)                                      |
| CSR automation                    | [`cluster/kubelet-csr-approver/README.md`](cluster/apps/kubelet-csr-approver/README.md) |
| Talos lifecycle overview          | [`talos/README.md`](talos/README.md)                                                    |
| Talos machine lifecycle deep dive | [`talos/docs/machine-lifecycle.md`](talos/docs/machine-lifecycle.md)                    |
| Infrastructure                    | [`infra/README.md`](infra/README.md)                                                    |

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

### Tooling and automation

- `task` orchestrates repeatable workflows defined in `.taskfiles/`.
- Use Context7 MCP ([GitHub](https://github.com/upstash/context7),
  [Dashboard](https://context7.com/dashboard)) for authoritative upstream
  documentation retrieval.
- The devcontainer image supplies TalosCTL, kubectl, Flux, Helm, Terraform,
  SOPS, and supporting CLIs.
- Super-linter pipelines (`task dev-env:lint`) enforce markdownlint, prettier,
  textlint, and gitleaks checks.

## Support

Operational questions and incidents should be tracked via repository issues or
the internal on-call channel. Include runbook references, recent Flux reconcile
outputs, and Talos log excerpts in any escalation. Coordinate secrets
management or Talos image changes with the platform owner before modifying
production nodes.

## Changelog

TBD – record future readme updates and significant procedural changes here.
