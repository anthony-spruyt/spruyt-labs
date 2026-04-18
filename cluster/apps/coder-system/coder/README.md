# Coder - Self-Hosted Codespaces

## Overview

Coder is a self-hosted development environment platform that provides browser-based workspaces (similar to GitHub Codespaces) running as Kubernetes pods. It manages workspace lifecycle, authentication, and resource provisioning via Terraform templates.

> **Note**: HelmRelease resources are managed by Flux in flux-system namespace but deploy workloads to the target namespace specified in ks.yaml.

## Prerequisites

- Kubernetes cluster with Flux CD
- `cnpg-operator` - CloudNative-PG operator for PostgreSQL
- `plugin-barman-cloud` - CNPG Barman plugin for S3 backups
- `external-secrets` - ExternalSecretOperator for secret delivery
- `authentik` - Identity provider for OIDC authentication

## Operation

### Key Commands

```bash
# Check status
kubectl get pods -n coder-system
flux get helmrelease -n flux-system coder

# Force reconcile (GitOps approach)
flux reconcile kustomization coder --with-source

# View logs
kubectl logs -n coder-system -l app.kubernetes.io/name=coder

# Check CNPG cluster health
kubectl get cluster -n coder-system coder-cnpg-cluster

# Check workspace pods
kubectl get pods -n coder-workspaces -l app.kubernetes.io/name=coder-workspace
```

## Configuration

| Detail | Value |
| ------ | ----- |
| Helm chart | `coder` from `coder-charts` |
| Namespace | `coder-system` |
| External URL | `https://code.${EXTERNAL_DOMAIN}` |
| Auth | Authentik OIDC |
| Database | CNPG PostgreSQL (`coder-cnpg-cluster`) |
| Storage | Rook Ceph (`rbd-fast-delete`) |
| Metrics | Prometheus endpoint on `0.0.0.0:2112` |
| Ingress | Traefik + Cloudflare Tunnel |

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
