# spruyt-labs

[![CI](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/anthony-spruyt/spruyt-labs/actions/workflows/ci.yaml) [![Renovate](https://img.shields.io/badge/renovate-enabled-brightgreen?logo=renovatebot)](https://github.com/anthony-spruyt/spruyt-labs/issues?q=is%3Aissue+is%3Aopen+label%3Arenovate)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/anthony-spruyt/spruyt-labs/blob/main/LICENSE)

Talos Linux home lab cluster managed with FluxCD-driven GitOps workflows.

For development environment setup, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Purpose and Scope

This repository codifies the spruyt-labs baremetal environment, from Talos machine configuration through workload deployment. It documents the operational expectations for platform engineers, the tooling required to contribute changes, and the runbooks necessary to recover common failure modes.

Objectives:

- Provide an auditable single source of truth for cluster and infrastructure state.
- Describe the workflows for preparing, reviewing, and shipping cluster changes.
- Cross-reference component-level runbooks and external documentation.

## Architecture Overview

- **Operating system** – Talos Linux on 3 control-plane and 3 worker nodes. Talos image schematics and lifecycle procedures live in [`talos/README.md`](talos/README.md).
- **GitOps control plane** – FluxCD manages reconciliation for all Kubernetes resources defined under `cluster/`.
- **Networking** – Cilium supplies CNI, network policy, and BGP integrations. Worker nodes are interconnected via a Thunderbolt ring topology carrying Ceph cluster traffic.
- **Ingress** – Traefik handles internal ingress routing with Cloudflare tunnels (cloudflared) for remote access.
- **Storage** – Rook Ceph provides block, filesystem, and object storage with Velero handling backup and disaster recovery to AWS S3.
- **Caching** – Valkey provides Redis-compatible in-memory data storage.
- **Identity** – Authentik provides SSO and identity management.
- **Security** – Kyverno enforces admission policies; Falco provides runtime threat detection.
- **Secrets** – SOPS/Age for Git-encrypted secrets; External Secrets Operator for AWS Secrets Manager integration and cross-namespace secret sync with auto-rotation.
- **Observability** – VictoriaMetrics for metrics, Vector for log shipping, and Grafana for dashboards.

## Security Posture

### Pod Security Standards

The cluster enforces **baseline** Pod Security Standards by default.

- Namespaces without explicit labels → baseline enforcement
- Infrastructure namespaces (rook-ceph, observability, velero, etc.) → privileged (explicitly labeled)

### Admission & Runtime

- **Kyverno** enforces admission policies cluster-wide
- **Falco** provides runtime threat detection and alerting

### Secrets Management

- All application secrets encrypted with **SOPS/Age** at rest in Git
- **External Secrets Operator** syncs secrets from AWS Secrets Manager and handles cross-namespace secret distribution with auto-rotation
- No hardcoded credentials in manifests

### Network Policies

- Cilium CNI provides network policy enforcement
- Critical apps have CiliumNetworkPolicy restricting ingress/egress
- Default: allow-all (explicit policies required per app)

### External Access

- Public services via **Cloudflare Tunnel** (no direct ingress)
- Internal services protected by **LAN IP whitelist** middleware
- TLS certificates via cert-manager with ZeroSSL/Let's Encrypt

## Runbooks

| Document                                                               | Purpose                        |
| ---------------------------------------------------------------------- | ------------------------------ |
| [docs/bootstrap.md](docs/bootstrap.md)                                 | Initial cluster deployment     |
| [docs/maintenance.md](docs/maintenance.md)                             | Day-to-day operations          |
| [docs/disaster-recovery.md](docs/disaster-recovery.md)                 | Backup and recovery procedures |
| [docs/intel-hybrid-architecture.md](docs/intel-hybrid-architecture.md) | Hardware architecture notes    |
| [docs/workload-classification.md](docs/workload-classification.md)     | Workload priority tiers        |
| [.claude/rules/](.claude/rules/)                                       | Claude agent rules             |

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

### CI/CD

- **CI** — Kubeconform, Kyverno policy tests, Terraform validate, Trivy scan
- **Flux differ** — Detects drift on pull requests
- **Renovate** — Automated dependency updates

### Tooling

- `task --list` — Available automation tasks
- `.devcontainer/` — Pre-configured development environment
- `task dev-env:lint` — Validate changes before commit
