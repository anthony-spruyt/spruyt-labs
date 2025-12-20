# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Talos Linux home lab cluster managed with FluxCD-driven GitOps workflows. The repository codifies a bare-metal Kubernetes environment from Talos machine configuration through workload deployment.

**Key technologies:**

- **OS**: Talos Linux 1.11 on Bossgame E2 control planes and MS-01 workers
- **GitOps**: FluxCD for all Kubernetes resources under `cluster/`
- **CNI/Networking**: Cilium with BGP integration
- **Ingress**: Traefik with Cloudflare tunnels (cloudflared)
- **Storage**: Rook Ceph (block, filesystem, object) with Velero backups
- **Observability**: VictoriaMetrics + Grafana
- **Secrets**: SOPS with Age encryption

## Common Commands

All automation uses Taskfile. Run `task --list` to see available tasks.

### Development & Validation

```bash
task dev-env:lint              # Run mega-linter (markdownlint, yamllint, prettier, etc.)
task pre-commit:run            # Run pre-commit hooks locally
```

### Talos Operations

```bash
task talos:gen                 # Generate Talos machine configs via Talhelper
task talos:apply               # Apply config to all nodes
task talos:apply-c1            # Apply to control plane 1 (e2-1)
task talos:apply-w1            # Apply to worker 1 (ms-01-1)
talosctl health                # Check Talos cluster health
```

### Flux Operations

```bash
task flux:cap                  # Launch Flux Capacitor GUI (localhost:3333)
flux get kustomizations -A     # Check reconciliation status
flux reconcile kustomization <name> --with-source  # Force reconcile
flux logs --kind Kustomization --name <name> -n flux-system
```

### Terraform

```bash
task terraform:fmt             # Format all Terraform files
task terraform:validate        # Validate all workspaces
task terraform:init            # Initialize all workspaces
```

### Secrets

```bash
task sops:decrypt              # Decrypt SOPS files for local development
task sops:encrypt              # Encrypt SOPS files
```

### Debugging

```bash
task dev-env:priv-pod node=<node>  # Run privileged pod on specified node
```

## Architecture

### Directory Structure

| Path                              | Purpose                                                                                                            |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `cluster/`                        | Flux GitOps definitions - all Kubernetes resources                                                                 |
| `cluster/apps/<namespace>/<app>/` | Application manifests with `ks.yaml` (Flux Kustomization), `app/release.yaml` (HelmRelease), and `app/values.yaml` |
| `cluster/flux/`                   | Flux bootstrap, controllers, source repositories                                                                   |
| `cluster/flux/meta/repositories/` | Helm, Git, and OCI source definitions                                                                              |
| `talos/`                          | Talos configuration, patches, and lifecycle docs                                                                   |
| `talos/talconfig.yaml`            | Talhelper cluster topology definition                                                                              |
| `talos/clusterconfig/`            | Generated machine configs (gitignored)                                                                             |
| `infra/terraform/`                | Terraform Cloud workspaces for AWS resources                                                                       |
| `.taskfiles/`                     | Task automation organized by component                                                                             |

### Application Layout Pattern

Each app follows this structure:

```
cluster/apps/<namespace>/<app>/
├── ks.yaml                    # Flux Kustomization
├── README.md                  # Component runbook
└── app/
    ├── kustomization.yaml     # Kustomize config
    ├── release.yaml           # HelmRelease
    └── values.yaml            # Chart values
```

### Flux Reconciliation Flow

1. `cluster/flux/cluster/ks.yaml` - Entry point aggregating all kustomizations
2. `cluster/flux/meta/` - Cluster settings, SOPS secrets, repository sources
3. `cluster/apps/` - Workload namespaces reconciled after meta layer

### Secrets Management

- SOPS with Age encryption for all secrets
- Flux decrypts using `sops-age` secret in `flux-system` namespace
- Encrypted files: `*.sops.yaml`, `cluster-secrets.sops.yaml`
- Age identity required: typically at `~/.config/sops/age/keys.txt`

## Constraints

1. **No Python scripts** - Strictly prohibited for automation or troubleshooting
2. **No SSH access** - Talos nodes administered only via `talosctl`, Flux, or Kubernetes APIs
3. **Automation first** - Prefer Flux/Terraform declarative configs over manual intervention
4. **Validation required** - Run `task dev-env:lint` before committing changes
5. **Use Taskfile** - Execute operations using `task` commands rather than raw CLI

## Workflow for Changes

### Kubernetes Manifests

1. Verify resource type exists: `kubectl api-resources`
2. Check field schema: `kubectl explain <resource>.<field> --recursive`
3. Retrieve current state: `kubectl get <resource> -n <ns> -o yaml`
4. Make changes in appropriate `cluster/apps/` location
5. Run `task dev-env:lint`
6. Commit and push; Flux reconciles automatically
7. Verify: `flux get kustomizations -n flux-system`

### Talos Configuration

1. Modify `talos/talconfig.yaml` or patches under `talos/patches/`
2. Run `task talos:gen` to regenerate configs
3. Apply: `task talos:apply-c1` (or specific node task)
4. Verify: `talosctl health`

### Terraform Infrastructure

1. Navigate to workspace: `cd infra/terraform/aws/<workspace>`
2. Run `task terraform:fmt` and `task terraform:validate`
3. Plan: `terraform plan -out plan.tfplan`
4. Apply: `terraform apply plan.tfplan`

## Key References

- Runbook standards: `README.md#runbook-standards`
- Talos lifecycle: `talos/README.md`, `talos/docs/machine-lifecycle.md`
- Flux operations: `cluster/flux/README.md`
- App documentation: `cluster/apps/README.md`
- Core operational rules: `.kilocode/rules/core_rules.md`
