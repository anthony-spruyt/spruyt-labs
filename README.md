# spruyt-labs

[![CI](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/ci.yaml) [![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovatebot)](https://github.com/anthony-spruyt/spruyt-labs/issues?q=is%3Aissue+is%3Aopen+label%3Arenovate)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/anthony-spruyt/spruyt-labs/blob/main/LICENSE)

Talos Linux home lab cluster on bare metal, managed with FluxCD GitOps. Everything from Talos machine config to workloads is declared in this repo.

For the development environment, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Architecture

- **Operating system** – Talos Linux on 3 control-plane (Bossgame E2) and 3 worker (MS-01) nodes. Machine config is generated with [topf](https://github.com/postfinance/topf); see [`talos/README.md`](talos/README.md).
- **GitOps** – Flux Operator runs Flux, which reconciles everything under `cluster/`.
- **Networking** – Cilium for CNI, kube-proxy replacement, network policy and BGP. The workers form a Thunderbolt ring that carries Ceph cluster traffic.
- **Ingress** – Traefik for routing; Cloudflare Tunnel (cloudflared) for public access, with no direct inbound ports.
- **Storage** – Rook Ceph for block, filesystem and object storage.
- **Backup** – Velero to S3 for Kubernetes objects and labelled PVCs; CloudNativePG with the barman-cloud plugin for PostgreSQL.
- **Caching** – Valkey (Redis-compatible).
- **Identity** – Authentik for SSO.
- **Security** – Kyverno admission policies; Falco runtime detection.
- **Secrets** – SOPS/Age in Git; External Secrets Operator copies secrets between namespaces.
- **Observability** – VictoriaMetrics, VictoriaLogs (with Vector) and VictoriaTraces, with Grafana dashboards.
- **Power** – NUT and `shutdown-orchestrator` shut the cluster down cleanly on UPS battery.
- **Cloud infrastructure** – Terraform Cloud workspaces under [`infra/`](infra/README.md) for S3 buckets and the Cloudflare tunnel.

## Security Posture

- **Pod Security Standards** – Talos enforces `baseline` for unlabelled namespaces. Most app namespaces are labelled `restricted`; `privileged` only where a workload needs host access.
- **Network policies** – nearly every namespace has CiliumNetworkPolicies restricting ingress and egress.
- **External access** – public services only through Cloudflare Tunnel. Internal services sit behind Traefik's `lan-ip-whitelist` middleware.
- **TLS** – cert-manager with Let's Encrypt and ZeroSSL issuers.
- **Secrets** – encrypted with SOPS/Age at rest in Git, never in plain manifests.

## Runbooks

| Document                                                               | Purpose                                        |
| ---------------------------------------------------------------------- | ---------------------------------------------- |
| [docs/bootstrap.md](docs/bootstrap.md)                                 | Build the cluster from bare metal              |
| [docs/maintenance.md](docs/maintenance.md)                             | Health checks, reboots, Talos and K8s upgrades |
| [docs/disaster-recovery.md](docs/disaster-recovery.md)                 | Node, etcd, database and Velero recovery       |
| [docs/releases.md](docs/releases.md)                                   | Container image releases (release-please)      |
| [docs/intel-hybrid-architecture.md](docs/intel-hybrid-architecture.md) | P-core / E-core tuning on the MS-01 workers    |
| [docs/workload-classification.md](docs/workload-classification.md)     | Priority classes and CPU limit policy          |

## Component Documentation

| Component            | Documentation                                      |
| -------------------- | -------------------------------------------------- |
| Cluster applications | [`cluster/apps/README.md`](cluster/apps/README.md) |
| Flux                 | [`cluster/flux/README.md`](cluster/flux/README.md) |
| Talos                | [`talos/README.md`](talos/README.md)               |
| Infrastructure       | [`infra/README.md`](infra/README.md)               |
| Agent rules          | [`.claude/rules/`](.claude/rules/)                 |

## CI/CD

- **CI** (`.github/workflows/ci.yaml`, synced from repo-operator) – runs on pull requests and pushes to `main`: MegaLinter, then the repo's own checks in `ci-repo.yaml` (kubeconform, Kyverno policy tests, bats and Terraform validate, each only when its area changed), then repo-operator's shared image job, which tests and builds the changed services in `cmd/`.
- **Trivy** – daily filesystem and image scan.
- **Releases** – release-please publishes container images; see [docs/releases.md](docs/releases.md).
- **Renovate** – automated dependency updates.

## Tooling

- `task --list` – available automation tasks
- `task dev-env:lint` – run MegaLinter locally before committing
- `.devcontainer/` – pre-configured development environment
