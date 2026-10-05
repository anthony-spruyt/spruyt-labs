# CLAUDE.md

Talos Linux homelab GitOps repository on bare metal. No SSH to Talos nodes - use `talosctl`, Flux, or Kubernetes APIs.

## Architecture

| Layer         | Technology                  | Purpose                                |
| ------------- | --------------------------- | -------------------------------------- |
| OS            | Talos Linux                 | Immutable, API-driven Kubernetes OS    |
| GitOps        | FluxCD                      | Reconciles `cluster/` to cluster state |
| CNI           | Cilium                      | Networking, network policies, BGP      |
| Ingress       | Traefik + Cloudflare Tunnel | Routing, no direct public ingress      |
| Storage       | Rook Ceph                   | Block, filesystem, object storage      |
| Backup        | Velero + S3                 | Disaster recovery                      |
| Cache         | Valkey                      | Redis-compatible in-memory store       |
| Observability | VictoriaMetrics + Grafana   | Metrics, dashboards                    |
| Secrets       | SOPS/Age                    | Encrypted at rest in Git               |

## Hard Rules

1. **Declarative only** - No manual kubectl patches for config changes; use Flux, Terraform, Talos configs. Operational commands (restart, scale, drain) via kubectl are permitted.
2. **Trunk-based** - Commit straight to `main` and push without asking. Open a PR only for large, risky work. Mergify exists only to auto-merge bot PRs (Renovate etc.) and is not a merge gate; merge PRs directly with `gh pr merge --squash` (squash is the only merge method the repo allows) and ignore its approval check.
3. **No git amend** - Always new commits
4. **No hardcoded domains** - Use `${EXTERNAL_DOMAIN}` substitution

## Codebase

| Path                       | Purpose                                      |
| -------------------------- | -------------------------------------------- |
| `cluster/apps/<ns>/<app>/` | Application deployments                      |
| `cluster/flux/meta/`       | Flux config, cluster secrets                 |
| `talos/`                   | Talos machine configs                        |
| `infra/terraform/`         | Cloud infrastructure (AWS backups, OIDC)     |
| `cmd/`                     | Go services (containers deployed to cluster) |
| `ts/`                      | TypeScript services (agent-queue-worker)     |
| `.taskfiles/`              | Automation (`task --list`)                   |
| `docs/`                    | Human runbooks (bootstrap, DR, maintenance)  |

## Tool Usage

Read and edit files with the `Read` and `Edit` tools rather than `cat`/`head`/`tail` or `sed -i`/`awk -i`; hooks warn on the shell forms. Search with `grep`, `rg`, or `find` through Bash.
