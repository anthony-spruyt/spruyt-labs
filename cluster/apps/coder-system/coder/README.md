# Coder - Self-Hosted Codespaces

## Overview

Coder is a self-hosted development environment platform that provides browser-based workspaces (similar to GitHub Codespaces) running as Kubernetes pods. It manages workspace lifecycle, authentication, and resource provisioning via Terraform templates.

## Prerequisites

- `cnpg-operator` - CloudNative-PG operator for PostgreSQL
- `plugin-barman-cloud` - CNPG Barman plugin for S3 backups
- `external-secrets` - ExternalSecretOperator for secret delivery
- `authentik` - Identity provider for OIDC authentication

## Configuration

| Detail          | Value                                      |
| --------------- | ------------------------------------------ |
| Helm chart      | `coder` from `coder-charts`                |
| Release channel | Stable only (see Operations)               |
| Namespace       | `coder-system`                             |
| External URL    | `https://code.${EXTERNAL_DOMAIN}`          |
| Auth            | Authentik OIDC                             |
| Database        | CNPG PostgreSQL (`coder-cnpg-cluster`)     |
| Storage         | Rook Ceph block storage available          |
| Metrics         | Prometheus endpoint on `0.0.0.0:2112`      |
| Ingress         | Traefik + Cloudflare Tunnel                |
| Server image    | Unpinned; follows the chart's `appVersion` |

## Operations

### Release channel: stable only

Coder ships two channels from the same Helm repository. Mainline is cut from `main` on the first Tuesday of each month; stable is the previous mainline, promoted after roughly a month in the field.

Both are published as plain semver chart versions, and every GitHub release carries `prerelease=false`, so no Renovate `versioning` or `ignoreUnstable` setting can tell them apart — a newer mainline chart simply looks like an available upgrade.

This deployment tracks **stable only**. Expect the pinned chart version to sit roughly one minor behind the newest version visible in the Helm repository; that gap is intentional, not a missed upgrade.

The mechanism lives in `.github/renovate-overrides.json5`:

- A `coder-stable` custom datasource reads `https://api.github.com/repos/coder/coder/releases/latest`. Coder's own `install.sh` resolves its `--stable` flag by following that same redirect, which makes the GitHub "latest release" marker the authoritative stable pointer.
- The `flux` manager is disabled for this chart, so the Helm repository index no longer proposes mainline.
- A `# renovate:` annotation above `version:` in `release.yaml` binds the pin to that datasource.

### Server image tag

`coder.image.tag` is deliberately left empty in `values.yaml`. The chart falls back to `v{{ .Chart.AppVersion }}`, which always equals the pinned chart version, so the server and chart stay in lockstep on one tracked version.

A pinned tag here would drift: Renovate's `helm-values` manager does not recognise Coder's `image.repo` / `image.tag` shape, so it never saw the key, and every chart bump left the image behind until someone edited it by hand.

This is the one image-bearing `values.yaml` in the repository without a `@sha256:` digest — a consequence of the same blind spot, since Renovate cannot maintain a digest it cannot see.

## Troubleshooting

### Common Issues

1. **Coder pod fails to start - database connection error**

   - **Symptom**: Pod crashes with PostgreSQL connection refused
   - **Resolution**: Check CNPG cluster is ready: `kubectl get cluster -n coder-system coder-cnpg-cluster`

2. **OIDC login fails**

   - **Symptom**: Login redirect fails or token error
   - **Resolution**: Verify Authentik application is configured and `coder-oauth-credentials` ExternalSecret is synced: `kubectl get externalsecret -n coder-system`

3. **Workspace pod stuck pending**

   - **Symptom**: Workspace created in Coder UI but pod never starts
   - **Resolution**: Check workspace RBAC and PVC provisioning: `kubectl get pvc -n coder-workspaces`, `kubectl describe pod -n coder-workspaces -l app.kubernetes.io/name=coder-workspace`

4. **Metrics not scraped**

   - **Symptom**: No Coder metrics in VictoriaMetrics
   - **Resolution**: Verify `CODER_PROMETHEUS_ADDRESS` is set to `0.0.0.0:2112` and the `allow-metrics-ingress` network policy allows vmagent ingress on port 2112

## References

- [Coder Documentation](https://coder.com/docs)
- [Coder Helm Chart](https://github.com/coder/coder/tree/main/helm)
- [CloudNative-PG Documentation](https://cloudnative-pg.io/documentation/)
