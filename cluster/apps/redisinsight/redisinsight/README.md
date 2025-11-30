# RedisInsight Runbook

## Purpose and Scope

RedisInsight provides a modern web-based GUI for managing Redis and Valkey databases, enabling developers and administrators to interact with data structures, monitor performance, and execute commands through an intuitive interface.

Objectives:

- Simplify database administration tasks
- Provide real-time monitoring capabilities
- Support development workflows with features like command history, data visualization, and bulk operations

## Directory Layout

| Path                       | Description                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------- |
| `ks.yaml`                  | Flux Kustomization resource defining the RedisInsight deployment                                      |
| `README.md`                | This operational runbook and component documentation                                                  |
| `app/kustomization.yaml`   | Kustomization overlay for Helm release configuration                                                  |
| `app/kustomizeconfig.yaml` | Kustomize configuration for resource transformations                                                  |
| `app/release.yaml`         | HelmRelease manifest with chart references and values overrides                                       |
| `app/values.yaml`          | Helm chart values configuration including security contexts, resource limits, and service definitions |

## Operational Runbook

### Summary

This runbook covers the deployment and management of RedisInsight, a web-based Redis/Valkey database management interface, ensuring secure access through Traefik ingress with TLS termination and proper resource constraints.

**Maintenance Note**: Review this runbook quarterly to ensure version information, procedures, and references remain current with RedisInsight releases and cluster infrastructure changes.

### Preconditions

- Flux reconciliation must be operational (`kubectl get kustomizations -n flux-system`)
- Valkey dependency deployed and accessible (external Redis/Valkey instance required for database connections)
- Cluster issuer configured for TLS certificate generation
- Traefik ingress controller operational with middleware for rate limiting and compression
- External domain configured for LAN access routing

### Procedure

#### Plan

1. Review current RedisInsight version compatibility with target Valkey/Redis instances
2. Verify ingress configuration matches cluster domain and TLS requirements
3. Confirm resource limits align with cluster capacity and workload patterns
4. Validate security contexts meet cluster hardening standards

#### Apply

1. Update `app/values.yaml` with desired RedisInsight version and configuration
2. Modify ingress routes if domain or middleware requirements change
3. Commit changes and push to trigger Flux reconciliation
4. Monitor Flux kustomization status: `flux get kustomizations -n flux-system`

#### Validate

1. Confirm pod deployment: `kubectl get pods -n redisinsight`
2. Verify service endpoints: `kubectl get svc -n redisinsight`
3. Test ingress accessibility: `curl -k https://redisinsight.lan.${EXTERNAL_DOMAIN}`
4. Check certificate issuance: `kubectl get certificates -n redisinsight`

#### Rollback

1. Suspend HelmRelease: `flux suspend hr redisinsight -n redisinsight`
2. Revert commit to previous working version
3. Resume reconciliation: `flux reconcile hr redisinsight -n redisinsight --with-source`
4. Validate rollback completion with health checks

### Validation

- **Pod health**: `kubectl get pods -n redisinsight -o wide` (should show Running status)
- **Service access**: `kubectl get svc redisinsightsvc -n redisinsight` (port 5540 exposed)
- **Ingress routing**: `curl -I https://redisinsight.lan.${EXTERNAL_DOMAIN}` (HTTP 200 response)
- **TLS certificate**: `kubectl get certificate redisinsight-lan-${EXTERNAL_DOMAIN/./-} -n redisinsight` (Ready status)
- **Application logs**: `kubectl logs -n redisinsight deployment/redisinsight` (no critical errors)

### Troubleshooting

#### Connection refused or timeout errors

- **Diagnostics**: Check pod logs for startup failures: `kubectl logs -n redisinsight deployment/redisinsight`
- **Remediation**: Verify resource limits aren't causing OOM kills; increase memory limits if needed
- **Recovery**: Restart deployment: `kubectl rollout restart deployment/redisinsight -n redisinsight`

#### Ingress routing failures

- **Diagnostics**: Test Traefik ingress: `kubectl get ingressroute -n redisinsight`
- **Remediation**: Verify middleware namespaces match deployment namespace
- **Recovery**: Update ingress patches in `cluster/apps/traefik/traefik/ingress/redisinsight/kustomization.yaml`

#### TLS certificate issues

- **Diagnostics**: Check cert-manager status: `kubectl describe certificate -n redisinsight`
- **Remediation**: Ensure cluster issuer is functional and DNS names are correct
- **Recovery**: Delete and recreate certificate: `kubectl delete certificate -n redisinsight; flux reconcile kustomization traefik -n flux-system`

#### Resource limit exceeded

- **Diagnostics**: Check pod events: `kubectl describe pod -n redisinsight`
- **Remediation**: Adjust resource requests/limits in `app/values.yaml`
- **Recovery**: Update HelmRelease values and reconcile

### Escalation

- Contact platform operations for persistent deployment failures or cluster-level ingress issues
- Escalate to infrastructure team for TLS certificate generation problems
- Reference RedisInsight upstream documentation for application-specific configuration issues
- Open repository issue for runbook updates or missing dependency documentation

## Validation and Testing

| Tool    | Command                                                          | Expected Output                               |
| ------- | ---------------------------------------------------------------- | --------------------------------------------- |
| kubectl | `kubectl get pods -n redisinsight`                               | Running status for redisinsight pod           |
| kubectl | `kubectl get svc -n redisinsight`                                | redisinsightsvc service with port 5540        |
| flux    | `flux get helmreleases -n redisinsight`                          | redisinsight HelmRelease in Ready state       |
| curl    | `curl -k https://redisinsight.lan.${EXTERNAL_DOMAIN}`            | HTTP 200 response with RedisInsight interface |
| kubectl | `kubectl logs deployment/redisinsight -n redisinsight --tail=50` | Application startup logs without errors       |

## References and Cross-links

- [Root README](../../README.md) — Cluster architecture and operational workflows
- [RedisInsight documentation](https://redis.com/redis-enterprise/redis-insight/) — Official GUI features and usage guide
- [Valkey documentation](https://valkey.io/) — Compatible Redis-compatible database
- [Flux HelmRelease reference](https://fluxcd.io/flux/components/helm/helmreleases/) — GitOps deployment patterns
