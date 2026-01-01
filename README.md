# spruyt-labs

[![Lint](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/lint.yaml/badge.svg)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/lint.yaml)
[![Kubeconform](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/kubeconform.yaml/badge.svg)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/kubeconform.yaml)
[![Kyverno](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/kyverno-test.yaml/badge.svg)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/kyverno-test.yaml)
[![Terraform](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/terraform-validate.yaml/badge.svg)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/terraform-validate.yaml)
[![Flux Diff](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/flux-differ.yaml/badge.svg)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/flux-differ.yaml)
[![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovatebot)](https://github.com/anthony-spruyt/spruyt-labs/issues?q=is%3Aissue+is%3Aopen+label%3Arenovate)

Talos Linux home lab cluster managed with FluxCD-driven GitOps workflows.

## Development Environment

This repository uses a VS Code devcontainer for a consistent development experience.

### Prerequisites

- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) or Docker Engine
- SSH agent running with keys loaded (see [SSH Agent Setup](#ssh-agent-setup))

### Host Directory Structure

The devcontainer expects these directories on your host machine:

```text
~/.secrets/
├── .env                    # Environment variables (loaded via --env-file)
├── .terraform.d/           # Terraform credentials and plugin cache
├── age.key                 # SOPS Age private key
├── kubeconfig              # Kubernetes cluster config
├── talosconfig             # Talos cluster config
└── ...                     # Other secrets as needed

~/.claude/                  # Claude Code settings and memory
```

Create the required structure:

```bash
mkdir -p ~/.secrets/.terraform.d ~/.claude
touch ~/.secrets/.env
```

The `.env` file sets environment variables and paths to secrets:

```bash
GH_TOKEN=<github-token>
CONTEXT7_API_KEY=<context7-key>
SOPS_AGE_KEY_FILE=/home/vscode/.secrets/age.key
KUBECONFIG=/home/vscode/.secrets/kubeconfig
TALOSCONFIG=/home/vscode/.secrets/talosconfig
```

### SSH Agent Setup

The devcontainer uses SSH agent forwarding via socket mount. Your private keys stay on
the host and are never copied into the container.

**Requirements:**

- SSH agent running with your key loaded
- `SSH_AUTH_SOCK` environment variable set and exported

**Linux/WSL:**

```bash
# Start agent and add key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Verify SSH_AUTH_SOCK is set
echo $SSH_AUTH_SOCK
```

For passphrase-protected keys, use `keychain` to persist across sessions:

```bash
# Install: sudo apt install keychain
# Add to ~/.bashrc or ~/.zshrc:
eval "$(keychain --eval --agents ssh id_ed25519)"
```

`keychain` prompts for your passphrase once per reboot and reuses the agent across terminals.

**macOS:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Keys added with `--apple-use-keychain` persist across restarts. The `SSH_AUTH_SOCK` is
set automatically by macOS.

**Windows (Git Bash):**

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Or enable the OpenSSH Authentication Agent service in Windows Services and ensure
`SSH_AUTH_SOCK` is set in your environment.

### Opening the Devcontainer

1. Ensure SSH agent is running and `SSH_AUTH_SOCK` is set
2. Clone the repository
3. Open the folder in VS Code
4. When prompted, click "Reopen in Container" (or run `Dev Containers: Reopen in Container` from the command palette)

The container uses Docker-in-Docker for running containers (MegaLinter, etc.) without
mounting the host Docker socket.

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

## Security Posture

### Pod Security Standards

The cluster enforces **baseline** Pod Security Standards by default (Kubernetes 1.34).

- Namespaces without explicit labels → baseline enforcement
- Infrastructure namespaces (rook-ceph, observability, velero, etc.) → privileged
  (explicitly labeled)

### Secrets Management

- All application secrets encrypted with **SOPS/Age**
- No hardcoded credentials in manifests
- External Secrets Operator available for future AWS Secrets Manager integration

### Network Policies

- Cilium CNI provides network policy enforcement
- Critical apps have CiliumNetworkPolicy restricting ingress/egress
- Default: allow-all (explicit policies required per app)

### External Access

- Public services via **Cloudflare Tunnel** (no direct ingress)
- Internal services protected by **LAN IP whitelist** middleware
- TLS certificates via cert-manager with ZeroSSL/Let's Encrypt

## Directory Layout

<!-- markdownlint-disable MD013 -->

| Path               | Description                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| `cluster/`         | Flux GitOps definitions for core, apps, CRDs, and machine overlays.      |
| `cluster/apps/`    | Workload manifests grouped by namespace and Helm release overlays.       |
| `cluster/flux/`    | Flux bootstrap resources, controllers, and repository definitions.       |
| `infra/terraform/` | Terraform workspaces for AWS backups, OIDC, and supporting cloud assets. |
| `talos/`           | Talos schematics, graceful shutdown steps, and upgrade guidance.         |
| `docs/`            | Runbooks (bootstrap, maintenance, DR) and shared rules.                  |
| `.taskfiles/`      | Taskfile automation for Talos, Flux, Terraform, and developer tooling.   |
| `.devcontainer/`   | Development container bootstrap for a consistent CLI toolchain.          |

<!-- markdownlint-enable MD013 -->

## Runbooks

| Document                                               | Purpose                          |
| ------------------------------------------------------ | -------------------------------- |
| [docs/bootstrap.md](docs/bootstrap.md)                 | Initial cluster deployment       |
| [docs/maintenance.md](docs/maintenance.md)             | Day-to-day operations            |
| [docs/disaster-recovery.md](docs/disaster-recovery.md) | Backup and recovery procedures   |
| [.claude/rules/](.claude/rules/)                       | Claude agent rules               |

## Troubleshooting Matrix

Common failure modes across the cluster. For component-specific issues, reference the app READMEs.

<!-- markdownlint-disable MD013 -->

| Failure Mode                       | Diagnostics                                        | Remediation                                                |
| ---------------------------------- | -------------------------------------------------- | ---------------------------------------------------------- |
| Flux reconciliation failures       | `kubectl get ks -n flux-system`, `flux logs`       | Fix Git auth, SOPS, or dependency issues; `flux reconcile` |
| Talos upgrade pitfalls             | `talosctl dmesg`, `talosctl logs -k`               | Reapply prior config, verify SecureBoot schematic          |
| Rook Ceph storage issues           | `ceph status`, `ceph crash ls` via rook-ceph-tools | Archive crashes, check OSD maintenance modes               |
| Container runtime crashes          | `talosctl logs containerd`, `talosctl logs cri`    | Investigate kernel/runtime problems                        |
| Helm chart rendering errors        | `flux logs --kind HelmRelease -n <ns>`             | Correct values syntax, align with upstream docs            |
| Application unhealthy post-upgrade | `kubectl get events -n <ns>`, workload logs        | Revert commit, suspend HelmRelease, rollback image         |
| Nodes never join                   | `talosctl logs kubelet`, verify CSR                | Ensure certificate subject matches node name               |

<!-- markdownlint-enable MD013 -->

## References

### Component READMEs

| Component            | Documentation                                      |
| -------------------- | -------------------------------------------------- |
| Cluster applications | [`cluster/apps/README.md`](cluster/apps/README.md) |
| Flux bootstrap       | [`cluster/flux/README.md`](cluster/flux/README.md) |
| Talos lifecycle      | [`talos/README.md`](talos/README.md)               |
| Infrastructure       | [`infra/README.md`](infra/README.md)               |

### External Documentation

- [Talos Linux](https://www.talos.dev/) — OS configuration and upgrades
- [FluxCD](https://fluxcd.io/) — GitOps controller
- [Cilium](https://docs.cilium.io/) — CNI and network policy
- [Traefik](https://doc.traefik.io/) — Ingress routing
- [Rook Ceph](https://rook.io/docs/rook/latest/) — Storage operator
- [Velero](https://velero.io/) — Backup and restore
- [VictoriaMetrics](https://docs.victoriametrics.com/) — Monitoring
- [CloudNativePG](https://cloudnative-pg.io/docs/) — PostgreSQL operator

### Tooling

- `task --list` — Available automation tasks
- `.devcontainer/` — Pre-configured development environment
- `task dev-env:lint` — Validate changes before commit
