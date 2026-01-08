# CLAUDE.md

Talos Linux homelab GitOps repository on bare metal. No SSH access - use `talosctl`, Flux, or Kubernetes APIs.

## Architecture

| Layer | Technology | Purpose |
|-------|------------|---------|
| OS | Talos Linux | Immutable, API-driven Kubernetes OS |
| GitOps | FluxCD | Reconciles `cluster/` to cluster state |
| CNI | Cilium | Networking, network policies, BGP |
| Ingress | Traefik + Cloudflare Tunnel | Routing, no direct public ingress |
| Storage | Rook Ceph | Block, filesystem, object storage |
| Backup | Velero + S3 | Disaster recovery |
| Cache | Valkey | Redis-compatible in-memory store |
| Observability | VictoriaMetrics + Grafana | Metrics, dashboards |
| Secrets | SOPS/Age | Encrypted at rest in Git |

## Hard Rules

1. **No secrets output** - Never display credentials or env var values
2. **Declarative only** - No manual kubectl patches; use Flux, Terraform, Talos configs
3. **No git push** - User pushes manually
4. **No git amend** - Always new commits
5. **No SOPS decrypt** - Never decrypt secrets via CLI
6. **No hardcoded domains** - Use `${EXTERNAL_DOMAIN}` substitution
7. **Explicit git add** - Only stage files YOU changed; NEVER `git add -A` or `.`

## Codebase

| Path | Purpose |
|------|---------|
| `cluster/apps/<ns>/<app>/` | Application deployments |
| `cluster/flux/meta/` | Flux config, cluster secrets |
| `talos/` | Talos machine configs |
| `infra/terraform/` | Cloud infrastructure (AWS backups, OIDC) |
| `.taskfiles/` | Automation (`task --list`) |
| `docs/` | Human runbooks (bootstrap, DR, maintenance) |

## Tool Usage

Use Claude's native tools instead of shell commands:

| Task | Use | Avoid |
|------|-----|-------|
| Read files | `Read` tool | `cat`, `head`, `tail` |
| Search content | `Grep` tool | `grep`, `rg` |
| Find files | `Glob` tool | `find`, `ls -R` |
| Edit files | `Edit` tool | `sed -i`, `awk -i` |
| List env keys | `env \| cut -d= -f1` | `env`, `printenv`, `echo $VAR` |
